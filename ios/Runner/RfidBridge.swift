import Flutter
import UIKit
import CoreBluetooth
import RFIDManager

/// Native iOS bridge for Chainway BLE UHF (tray + R6) using RFIDManager SDK.
/// Mirrors Android MethodChannel `com.loyalstring.rfid/uhf` + EventChannel `com.loyalstring.rfid/tags`.
final class RfidBridge: NSObject {
  static let shared = RfidBridge()

  private let methodChannelName = "com.loyalstring.rfid/uhf"
  private let eventChannelName = "com.loyalstring.rfid/tags"

  private var eventSink: FlutterEventSink?
  private var methodChannel: FlutterMethodChannel?

  private enum BleMode: String {
    case none
    case tray
    case r6
  }

  private var bleMode: BleMode = .none
  private var deviceAddress: String = ""
  private var connected = false
  private var isScanning = false
  private var scanningPermitted = false
  private var inventoryScanMode = false
  private var activeInventorySession = false

  private var searchTags = Set<String>()
  private var matchEpcs = Set<String>()
  private var inventoryScopeEpcs = Set<String>()

  private var pendingPeripheral: CBPeripheral?
  private var discovered: [String: (name: String, peripheral: CBPeripheral)] = [:]
  private let scanLock = NSLock()

  private let tagQueue = DispatchQueue(label: "com.loyalstring.rfid.tags")
  private var recentEmitAt: [String: TimeInterval] = [:]
  private let emitDedupMs: TimeInterval = 0.25

  func setup(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
    methodChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }

    let events = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
    events.setStreamHandler(self)

    RFIDBleManager.shared.setConnectStateUpdateBlock { [weak self] peripheral, state in
      self?.onConnectionState(peripheral: peripheral, state: state)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(true)
    case "initReader":
      result(true)
    case "prepareForScan":
      scanningPermitted = true
      result(true)
    case "haltScan":
      scanningPermitted = false
      inventoryScanMode = false
      inventoryScopeEpcs.removeAll()
      result(true)
    case "startScanning":
      let args = call.arguments as? [String: Any]
      let power = args?["power"] as? Int ?? 5
      let inventory = args?["inventory"] as? Bool ?? inventoryScanMode
      result(startInventory(power: power, inventory: inventory))
    case "stopScanning":
      result(stopInventory())
    case "setPower":
      let power = (call.arguments as? [String: Any])?["power"] as? Int ?? 5
      result(setPower(power))
    case "setSearchTags":
      let tags = ((call.arguments as? [String: Any])?["tags"] as? [String]) ?? []
      searchTags = Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty })
      matchEpcs.removeAll()
      result(true)
    case "setMatchEpcs":
      let epcs = ((call.arguments as? [String: Any])?["epcs"] as? [String]) ?? []
      searchTags.removeAll()
      matchEpcs = Set(epcs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty })
      result(true)
    case "setInventoryScanMode":
      inventoryScanMode = ((call.arguments as? [String: Any])?["enabled"] as? Bool) ?? false
      if inventoryScanMode { searchTags.removeAll() }
      result(true)
    case "playBeep":
      DispatchQueue.global(qos: .utility).async {
        _ = RFIDBleManager.shared.triggerBeep(duration: 40)
      }
      result(true)
    case "clearMatchEpcs":
      matchEpcs.removeAll()
      result(true)
    case "clearSearchTags":
      searchTags.removeAll()
      result(true)
    case "clearInventoryScope":
      inventoryScopeEpcs.removeAll()
      result(true)
    case "addInventoryScopeEpcs":
      let epcs = ((call.arguments as? [String: Any])?["epcs"] as? [String]) ?? []
      for epc in epcs {
        let key = epc.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !key.isEmpty { inventoryScopeEpcs.insert(key) }
      }
      result(true)
    case "setTrayMode":
      let args = call.arguments as? [String: Any]
      let enabled = args?["enabled"] as? Bool ?? false
      let address = (args?["address"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      applyBleMode(enabled ? .tray : .none, address: address)
      result(statusMap(for: .tray))
    case "setR6Mode":
      let args = call.arguments as? [String: Any]
      let enabled = args?["enabled"] as? Bool ?? false
      let address = (args?["address"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      applyBleMode(enabled ? .r6 : .none, address: address)
      result(statusMap(for: .r6))
    case "getTrayStatus":
      result(statusMap(for: .tray))
    case "getR6Status":
      result(statusMap(for: .r6))
    case "listBondedBluetoothDevices":
      scanNearbyDevices(durationMs: 2800, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func statusMap(for mode: BleMode) -> [String: Any] {
    let enabled = bleMode == mode
    return [
      "enabled": enabled,
      "connected": enabled && connected,
      "address": enabled ? deviceAddress : (mode == bleMode ? deviceAddress : ""),
    ]
  }

  private func applyBleMode(_ mode: BleMode, address: String) {
    stopInventory()
    disconnectCurrent()
    bleMode = mode
    deviceAddress = address
    connected = false
    if mode != .none && !address.isEmpty {
      connect(to: address)
    }
  }

  private func disconnectCurrent() {
    if let p = pendingPeripheral {
      RFIDBleManager.shared.disconnectPeripheral(p)
    }
    pendingPeripheral = nil
    connected = false
  }

  private func connect(to address: String) {
    // Prefer already-discovered / connected peripherals.
    if let known = discovered[address]?.peripheral {
      pendingPeripheral = known
      RFIDBleManager.shared.connectPeripheral(peripheral: known, didFailToConnectBlock: { [weak self] _, _ in
        self?.emitConnection(false)
      })
      return
    }

    for p in RFIDBleManager.shared.retrieveConnectedPeripherals() {
      let id = p.identifier.uuidString
      if id.caseInsensitiveCompare(address) == .orderedSame || (p.name ?? "").caseInsensitiveCompare(address) == .orderedSame {
        pendingPeripheral = p
        RFIDBleManager.shared.connectPeripheral(peripheral: p, didFailToConnectBlock: { [weak self] _, _ in
          self?.emitConnection(false)
        })
        return
      }
    }

    // Scan briefly then connect when the UUID/name appears.
    RFIDBleManager.shared.scanForPeripherals { [weak self] peripheral, advertisementData, _ in
      guard let self = self else { return }
      let id = peripheral.identifier.uuidString
      let name = peripheral.name
        ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        ?? "RFID Reader"
      self.scanLock.lock()
      self.discovered[id] = (name, peripheral)
      self.scanLock.unlock()

      if id.caseInsensitiveCompare(address) == .orderedSame
          || name.caseInsensitiveCompare(address) == .orderedSame {
        RFIDBleManager.shared.stopForPeripherals()
        self.pendingPeripheral = peripheral
        RFIDBleManager.shared.connectPeripheral(peripheral: peripheral, didFailToConnectBlock: { [weak self] _, _ in
          self?.emitConnection(false)
        })
      }
    }
  }

  private func onConnectionState(peripheral: CBPeripheral, state: CBPeripheralState) {
    switch state {
    case .connected:
      pendingPeripheral = peripheral
      deviceAddress = peripheral.identifier.uuidString
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        _ = RFIDBleManager.shared.initialize()
        DispatchQueue.main.async {
          self?.connected = true
          self?.emitConnection(true)
        }
      }
    case .disconnected:
      connected = false
      emitConnection(false)
    default:
      break
    }
  }

  private func emitConnection(_ isConnected: Bool) {
    let event: String
    switch bleMode {
    case .tray:
      event = isConnected ? "TRAY_CONNECTED" : "TRAY_DISCONNECTED"
    case .r6:
      event = isConnected ? "R6_CONNECTED" : "R6_DISCONNECTED"
    case .none:
      return
    }
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(event)
    }
  }

  private func setPower(_ power: Int) -> Bool {
    guard bleMode != .none, connected else { return false }
    let res = RFIDBleManager.shared.setPower(power)
    return res.code == .success
  }

  private func startInventory(power: Int, inventory: Bool) -> Bool {
    guard scanningPermitted else { return false }
    if isScanning { return true }
    guard bleMode != .none, connected else { return false }

    activeInventorySession = inventory
    _ = setPower(power)

    isScanning = true
    let res = RFIDBleManager.shared.startInventory(
      filter: nil,
      inventoryParam: RFIDInventoryParam(unique: false),
      tagInfoListBlock: { [weak self] tagInfoList in
        self?.tagQueue.async {
          for tag in tagInfoList {
            self?.handleTag(tag)
          }
        }
      }
    )
    if res.code != .success {
      isScanning = false
      return false
    }
    return true
  }

  private func stopInventory() -> Bool {
    searchTags.removeAll()
    matchEpcs.removeAll()
    inventoryScanMode = false
    scanningPermitted = false
    inventoryScopeEpcs.removeAll()
    activeInventorySession = false
    isScanning = false
    let res = RFIDBleManager.shared.stopInventory()
    return res.code == .success
  }

  private func handleTag(_ tag: RFIDTagInfo) {
    guard isScanning else { return }
    let epc = tag.epc.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !epc.isEmpty else { return }
    if !shouldEmit(epc) { return }
    let rssi = "\(tag.rssi)"
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?("\(epc),\(rssi)")
    }
  }

  private func shouldEmit(_ epc: String) -> Bool {
    // BLE modes emit all tags (product matching in Flutter), same as Android tray path.
    if bleMode == .none {
      if inventoryScanMode {
        if !inventoryScopeEpcs.isEmpty && !inventoryScopeEpcs.contains(epc) { return false }
      } else {
        if !searchTags.isEmpty && !searchTags.contains(epc) { return false }
        if searchTags.isEmpty && !matchEpcs.isEmpty && !matchEpcs.contains(epc) { return false }
      }
    }
    let now = Date().timeIntervalSince1970
    if let last = recentEmitAt[epc], now - last < emitDedupMs { return false }
    recentEmitAt[epc] = now
    if recentEmitAt.count > 12000 { recentEmitAt.removeAll(keepingCapacity: true) }
    return true
  }

  private func scanNearbyDevices(durationMs: Int, result: @escaping FlutterResult) {
    scanLock.lock()
    discovered.removeAll()
    scanLock.unlock()

    for p in RFIDBleManager.shared.retrieveConnectedPeripherals() {
      let id = p.identifier.uuidString
      let name = p.name ?? "RFID Reader"
      scanLock.lock()
      discovered[id] = (name, p)
      scanLock.unlock()
    }

    RFIDBleManager.shared.scanForPeripherals { [weak self] peripheral, advertisementData, _ in
      guard let self = self else { return }
      // Prefer Chainway manufacturer prefix 0x47 0x20 when present; still accept others.
      if let data = advertisementData["kCBAdvDataManufacturerData"] as? Data,
         data.count >= 2, data[0] == 0x47, data[1] == 0x20 {
        // Chainway RFID family
      }
      let id = peripheral.identifier.uuidString
      let name = peripheral.name
        ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        ?? "RFID Reader"
      self.scanLock.lock()
      self.discovered[id] = (name, peripheral)
      self.scanLock.unlock()
    }

    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(durationMs)) {
      RFIDBleManager.shared.stopForPeripherals()
      self.scanLock.lock()
      let list: [[String: String]] = self.discovered.map { id, value in
        ["name": value.name, "address": id]
      }.sorted { ($0["name"] ?? "") < ($1["name"] ?? "") }
      self.scanLock.unlock()
      DispatchQueue.main.async {
        result(list)
      }
    }
  }
}

extension RfidBridge: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
