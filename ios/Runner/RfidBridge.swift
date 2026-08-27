import Flutter
import UIKit
import AVFoundation
import CoreBluetooth
import Combine
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
  private var isConnecting = false
  private var isScanning = false
  private var scanningPermitted = false
  private var inventoryScanMode = false
  private var activeInventorySession = false
  private var readerInitialized = false
  private var reconnectWorkItem: DispatchWorkItem?
  private var pendingConnectResult: ((Bool) -> Void)?
  private var connectTimeoutWorkItem: DispatchWorkItem?
  private var keyEventCancellable: AnyCancellable?
  private var lastR6TriggerAt: TimeInterval = 0
  private var lastScanPower: Int = 5

  private var searchTags = Set<String>()
  private var matchEpcs = Set<String>()
  private var inventoryScopeEpcs = Set<String>()
  private var sessionUniqueEpcs = Set<String>()

  private var pendingPeripheral: CBPeripheral?
  private var discovered: [String: (name: String, peripheral: CBPeripheral)] = [:]
  private let scanLock = NSLock()

  private let tagQueue = DispatchQueue(label: "com.loyalstring.rfid.tags")
  private var recentEmitAt: [String: TimeInterval] = [:]
  private let emitDedupMs: TimeInterval = 0.25

  private let scanSound = ScanSoundPlayer()

  func setup(messenger: FlutterBinaryMessenger) {
    if methodChannel != nil { return }
    methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
    methodChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }

    let events = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
    events.setStreamHandler(self)

    RFIDBleManager.shared.setConnectStateUpdateBlock { [weak self] peripheral, state in
      self?.onConnectionState(peripheral: peripheral, state: state)
    }

    // R6 sled hardware trigger → Flutter TRIGGER_CLICK (same as Android KeyEventCallback).
    // Prefer Combine publisher (official sample); also bind setKeyEvent so the peripheral
    // button path is explicitly enabled after BLE UHF init.
    keyEventCancellable = RFIDBleManager.shared.keyEventPublisher
      .receive(on: DispatchQueue.main)
      .sink { [weak self] event in
        self?.handleR6SledKey(isDown: event.isKeyDown, keyCode: event.keyCode)
      }
    bindR6KeyEventCallback()
  }

  private func bindR6KeyEventCallback() {
    RFIDBleManager.shared.setKeyEvent(
      keyDownBlock: { [weak self] keyCode in
        DispatchQueue.main.async {
          self?.handleR6SledKey(isDown: true, keyCode: keyCode)
        }
      },
      keyUpBlock: { [weak self] keyCode in
        DispatchQueue.main.async {
          self?.handleR6SledKey(isDown: false, keyCode: keyCode)
        }
      }
    )
  }

  /// R6-only: Chainway sample starts inventory from keyDown; also notify Flutter UI.
  private func handleR6SledKey(isDown: Bool, keyCode: Int) {
    guard bleMode == .r6, isDown else { return }
    let now = Date().timeIntervalSince1970
    if now - lastR6TriggerAt < 0.3 { return }
    lastR6TriggerAt = now
    NSLog(
      "R6 sled trigger keyCode=%d scanning=%@ connected=%@",
      keyCode,
      isScanning ? "YES" : "NO",
      (connected && readerInitialized) ? "YES" : "NO"
    )
    eventSink?("TRIGGER_CLICK")
    // Native start immediately (same as Android / Chainway sample).
    if !isScanning {
      scanningPermitted = true
      if connected && readerInitialized {
        _ = startInventory(power: lastScanPower, inventory: inventoryScanMode)
      } else if !deviceAddress.isEmpty {
        applyBleMode(.r6, address: deviceAddress)
        waitForConnection(timeout: 18) { [weak self] ok in
          guard let self = self, ok else { return }
          self.scanningPermitted = true
          _ = self.startInventory(power: self.lastScanPower, inventory: self.inventoryScanMode)
        }
      }
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
      scanSound.stopContinuous()
      result(true)
    case "startScanning":
      let args = call.arguments as? [String: Any]
      let power = args?["power"] as? Int ?? 5
      let inventory = args?["inventory"] as? Bool ?? inventoryScanMode
      lastScanPower = power
      if bleMode == .r6 && !(connected && readerInitialized) {
        let address = deviceAddress
        if address.isEmpty {
          result(false)
          return
        }
        applyBleMode(.r6, address: address)
        waitForConnection(timeout: 18) { [weak self] ok in
          guard let self = self else {
            result(false)
            return
          }
          result(ok ? self.startInventory(power: power, inventory: inventory) : false)
        }
      } else {
        result(startInventory(power: power, inventory: inventory))
      }
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
    case "addSearchTags":
      let tags = ((call.arguments as? [String: Any])?["tags"] as? [String]) ?? []
      for tag in tags {
        let key = tag.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !key.isEmpty { searchTags.insert(key) }
      }
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
      scanSound.playDeepBeep(trayBeep: true)
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
      if enabled && !address.isEmpty && !(connected && readerInitialized) {
        waitForConnection(timeout: 18) { [weak self] _ in
          result(self?.statusMap(for: .r6) ?? [
            "enabled": true,
            "connected": false,
            "address": address,
          ])
        }
      } else {
        result(statusMap(for: .r6))
      }
    case "getTrayStatus":
      result(statusMap(for: .tray))
    case "getR6Status":
      result(statusMap(for: .r6))
    case "listBondedBluetoothDevices":
      scanNearbyDevices(durationMs: 4500, result: result)
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
      "connecting": enabled && isConnecting,
    ]
  }

  /// Keep an existing BLE session when mode + address are unchanged.
  private func applyBleMode(_ mode: BleMode, address: String) {
    reconnectWorkItem?.cancel()
    reconnectWorkItem = nil

    if mode != .none,
       mode == bleMode,
       address.caseInsensitiveCompare(deviceAddress) == .orderedSame,
       !address.isEmpty {
      if connected || isConnecting {
        return
      }
      connect(to: address)
      return
    }

    // Stop inventory only — do not tear down BLE unless mode/address actually changes.
    if isScanning {
      _ = RFIDBleManager.shared.stopInventory()
      isScanning = false
      scanSound.stopContinuous()
    }

    if mode == .none {
      disconnectCurrent()
      bleMode = .none
      deviceAddress = ""
      connected = false
      isConnecting = false
      readerInitialized = false
      return
    }

    let switchingTarget =
      bleMode != mode ||
      deviceAddress.caseInsensitiveCompare(address) != .orderedSame

    if switchingTarget {
      disconnectCurrent()
      connected = false
      isConnecting = false
      readerInitialized = false
    }

    bleMode = mode
    deviceAddress = address
    if !address.isEmpty {
      connect(to: address)
    }
  }

  private func disconnectCurrent() {
    reconnectWorkItem?.cancel()
    reconnectWorkItem = nil
    isConnecting = false
    if let p = pendingPeripheral {
      RFIDBleManager.shared.disconnectPeripheral(p)
    }
    pendingPeripheral = nil
    connected = false
  }

  private func connect(to address: String) {
    let target = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !target.isEmpty else { return }

    if connected && deviceAddress.caseInsensitiveCompare(target) == .orderedSame {
      return
    }
    // Do not cancel / re-open while a connect handshake is already running.
    if isConnecting && deviceAddress.caseInsensitiveCompare(target) == .orderedSame {
      return
    }

    isConnecting = true
    deviceAddress = target

    let onFail: (CBPeripheral?, Error?) -> Void = { [weak self] _, _ in
      guard let self = self else { return }
      self.isConnecting = false
      self.emitConnection(false)
      self.scheduleReconnectIfNeeded()
    }

    // Prefer already-discovered / connected peripherals (UUID or name, e.g. R-41138282).
    if let known = peripheralMatching(target) {
      pendingPeripheral = known
      RFIDBleManager.shared.connectPeripheral(peripheral: known, didFailToConnectBlock: onFail)
      return
    }

    for p in RFIDBleManager.shared.retrieveConnectedPeripherals() {
      if matchesPeripheral(p, target: target) {
        pendingPeripheral = p
        RFIDBleManager.shared.connectPeripheral(peripheral: p, didFailToConnectBlock: onFail)
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
      self.discovered[name.uppercased()] = (name, peripheral)
      self.scanLock.unlock()

      if self.matchesPeripheral(peripheral, target: target)
          || name.caseInsensitiveCompare(target) == .orderedSame
          || name.uppercased().contains(target.uppercased()) {
        RFIDBleManager.shared.stopForPeripherals()
        self.pendingPeripheral = peripheral
        RFIDBleManager.shared.connectPeripheral(peripheral: peripheral, didFailToConnectBlock: onFail)
      }
    }

    // Stop open-ended discovery after a timeout; reconnect scheduler will retry.
    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
      guard let self = self else { return }
      RFIDBleManager.shared.stopForPeripherals()
      if !self.connected && !self.isConnecting {
        self.scheduleReconnectIfNeeded()
      }
    }
    // Watchdog: clear stuck handshake so reconnect can proceed.
    DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) { [weak self] in
      guard let self = self else { return }
      guard self.isConnecting, !self.connected else { return }
      self.isConnecting = false
      self.scheduleReconnectIfNeeded()
    }
  }

  private func peripheralMatching(_ target: String) -> CBPeripheral? {
    scanLock.lock()
    defer { scanLock.unlock() }
    if let exact = discovered[target]?.peripheral { return exact }
    let upper = target.uppercased()
    if let byName = discovered[upper]?.peripheral { return byName }
    for (key, value) in discovered {
      if key.caseInsensitiveCompare(target) == .orderedSame { return value.peripheral }
      if value.name.caseInsensitiveCompare(target) == .orderedSame { return value.peripheral }
      if value.name.uppercased().contains(upper) { return value.peripheral }
    }
    return nil
  }

  private func matchesPeripheral(_ peripheral: CBPeripheral, target: String) -> Bool {
    let id = peripheral.identifier.uuidString
    if id.caseInsensitiveCompare(target) == .orderedSame { return true }
    if let name = peripheral.name {
      if name.caseInsensitiveCompare(target) == .orderedSame { return true }
      if name.uppercased().contains(target.uppercased()) { return true }
    }
    return false
  }

  private func onConnectionState(peripheral: CBPeripheral, state: CBPeripheralState) {
    switch state {
    case .connecting:
      isConnecting = true
    case .connected:
      reconnectWorkItem?.cancel()
      reconnectWorkItem = nil
      pendingPeripheral = peripheral
      deviceAddress = peripheral.identifier.uuidString
      // Official Chainway sample: always initialize UHF after every BLE connect.
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let self = self else { return }
        _ = RFIDBleManager.shared.initialize()
        self.readerInitialized = true
        // R6 trigger buttons need key callback after UHF init.
        DispatchQueue.main.async {
          self.bindR6KeyEventCallback()
          self.isConnecting = false
          self.connected = true
          self.emitConnection(true)
          self.finishConnectWait(success: true)
        }
      }
    case .disconnected:
      // Ignore disconnect noise during an in-flight connect handshake.
      if isConnecting {
        return
      }
      connected = false
      readerInitialized = false
      emitConnection(false)
      finishConnectWait(success: false)
      scheduleReconnectIfNeeded()
    default:
      break
    }
  }

  private func waitForConnection(timeout: TimeInterval, completion: @escaping (Bool) -> Void) {
    if connected && readerInitialized {
      completion(true)
      return
    }
    connectTimeoutWorkItem?.cancel()
    pendingConnectResult = completion
    let timeoutWork = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      guard self.pendingConnectResult != nil else { return }
      let ok = self.connected && self.readerInitialized
      self.finishConnectWait(success: ok)
    }
    connectTimeoutWorkItem = timeoutWork
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
  }

  private func finishConnectWait(success: Bool) {
    connectTimeoutWorkItem?.cancel()
    connectTimeoutWorkItem = nil
    let callback = pendingConnectResult
    pendingConnectResult = nil
    callback?(success)
  }

  private func scheduleReconnectIfNeeded() {
    guard bleMode != .none, !deviceAddress.isEmpty else { return }
    if isConnecting || connected { return }
    reconnectWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      guard self.bleMode != .none,
            !self.connected,
            !self.isConnecting,
            !self.deviceAddress.isEmpty else { return }
      self.connect(to: self.deviceAddress)
    }
    reconnectWorkItem = work
    // Match Android: longer delay so GATT handshake is not cancelled.
    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
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
    guard bleMode != .none else { return false }

    // R6 sled: require BLE linked + UHF initialized (Chainway sample sequence).
    if bleMode == .r6 {
      guard connected, readerInitialized else { return false }
    } else {
      guard connected else { return false }
    }

    activeInventorySession = inventory
    sessionUniqueEpcs.removeAll()
    _ = setPower(power)

    isScanning = true
    if inventory {
      scanSound.startContinuous(trayBeep: true)
    }

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
      // Tray: keep strict failure. R6: keep session open — tags may still stream.
      if bleMode == .r6 {
        return true
      }
      isScanning = false
      scanSound.stopContinuous()
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
    sessionUniqueEpcs.removeAll()
    activeInventorySession = false
    isScanning = false
    scanSound.stopContinuous()
    let res = RFIDBleManager.shared.stopInventory()
    return res.code == .success
  }

  private func handleTag(_ tag: RFIDTagInfo) {
    guard isScanning else { return }
    let epc = tag.epc.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !epc.isEmpty else { return }
    if !shouldEmit(epc) { return }

    if !activeInventorySession {
      onProductTagSound(epc: epc)
    }

    let rssi = "\(tag.rssi)"
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?("\(epc),\(rssi)")
    }
  }

  private func onProductTagSound(epc: String) {
    let inserted = sessionUniqueEpcs.insert(epc).inserted
    guard inserted else { return }
    switch sessionUniqueEpcs.count {
    case 1:
      scanSound.playDeepBeep(trayBeep: true)
    case 2:
      scanSound.startContinuous(trayBeep: true)
    default:
      break
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
      self.discovered[name.uppercased()] = (name, peripheral)
      self.scanLock.unlock()
    }

    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(durationMs)) {
      RFIDBleManager.shared.stopForPeripherals()
      self.scanLock.lock()
      var seen = Set<String>()
      var list: [[String: String]] = []
      for (key, value) in self.discovered {
        // Skip name-index duplicates; keep UUID entries.
        if key.contains("-") || key.count > 20 {
          let address = value.peripheral.identifier.uuidString
          if seen.insert(address).inserted {
            list.append(["name": value.name, "address": address])
          }
        }
      }
      // Also include name-only entries if UUID map missed them.
      for (_, value) in self.discovered {
        let address = value.peripheral.identifier.uuidString
        if seen.insert(address).inserted {
          list.append(["name": value.name, "address": address])
        }
      }
      list.sort { ($0["name"] ?? "") < ($1["name"] ?? "") }
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

/// Phone speaker + optional tray hardware beep.
private final class ScanSoundPlayer {
  private var audioPlayer: AVAudioPlayer?
  private var continuousTimer: Timer?
  private let queue = DispatchQueue(label: "com.loyalstring.rfid.sound")

  init() {
    prepareSession()
    preparePlayer()
  }

  private func prepareSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, options: [.mixWithOthers])
      try session.setActive(true, options: [])
    } catch {
      // Non-fatal — system/tray beep may still work.
    }
  }

  private func preparePlayer() {
    guard let url = Bundle.main.url(forResource: "barcodebeep", withExtension: "mp3") else {
      return
    }
    do {
      audioPlayer = try AVAudioPlayer(contentsOf: url)
      audioPlayer?.prepareToPlay()
    } catch {
      audioPlayer = nil
    }
  }

  func playDeepBeep(trayBeep: Bool) {
    queue.async {
      if trayBeep {
        _ = RFIDBleManager.shared.triggerBeep(duration: 100)
      }
      DispatchQueue.main.async {
        self.audioPlayer?.enableRate = true
        self.audioPlayer?.rate = 0.7
        self.audioPlayer?.currentTime = 0
        self.audioPlayer?.play()
      }
    }
  }

  func startContinuous(trayBeep: Bool) {
    DispatchQueue.main.async {
      guard self.continuousTimer == nil else { return }
      self.audioPlayer?.enableRate = true
      self.audioPlayer?.rate = 1.0
      self.audioPlayer?.numberOfLoops = -1
      self.audioPlayer?.currentTime = 0
      self.audioPlayer?.play()
      if trayBeep {
        self.continuousTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
          DispatchQueue.global(qos: .utility).async {
            _ = RFIDBleManager.shared.triggerBeep(duration: 40)
          }
        }
      }
    }
  }

  func stopContinuous() {
    DispatchQueue.main.async {
      self.continuousTimer?.invalidate()
      self.continuousTimer = nil
      self.audioPlayer?.stop()
      self.audioPlayer?.numberOfLoops = 0
      self.audioPlayer?.currentTime = 0
    }
  }
}
