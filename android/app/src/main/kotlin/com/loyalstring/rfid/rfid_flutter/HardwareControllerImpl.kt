package com.loyalstring.rfid.rfid_flutter

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.SoundPool
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import java.util.HashMap
import java.util.HashSet
import java.util.LinkedHashMap
import java.util.LinkedHashSet
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Owns UART/BLE RFID, barcode, sounds, and tag polling.
 * Loaded only via [Class.forName] from [MainActivity] so DeviceAPI is not linked at splash.
 */
class HardwareControllerImpl(
    private val activity: FlutterActivity,
) : HardwareController {

    private var eventSink: EventChannel.EventSink? = null
    private var uhfFacade: UhfFacade? = null
    private lateinit var barcodeManager: BarcodeManager
    private lateinit var trayManager: TrayReaderManager

    private var isScanning = false
    private var executorService: ExecutorService? = null
    private var lastBarcodeKeyMs = 0L

    private var soundPool: SoundPool? = null
    private val soundMap = HashMap<Int, Int>()
    private val soundStreamIds = HashMap<Int, Int>()
    private var audioManager: AudioManager? = null
    private var volumeRatio = 1f
    /** Sparkle SearchViewModel lastSoundId / lastSoundPlayAt */
    private var lastSearchSoundId = -1
    private var lastSearchSoundPlayAt = 0L
    /** Same-tone gap: LED inventory floods tag reads; 15ms retrigger clicks/stutters. */
    private val searchSoundMinIntervalMs = 140L
    /** Allow a closer bucket to switch without waiting a full beep. */
    private val searchSoundSwitchMinMs = 45L
    /** Ignore brief weaker RSSI so close tone does not flip to far for ~1s. */
    private var lastCloseSearchSoundAt = 0L
    private val holdCloseSearchMs = 1800L

    private var searchTags = HashSet<String>()
    private val searchTagLock = Any()
    /** Ingest search keys off the platform thread so Start is not blocked. */
    private val tagSetExecutor = Executors.newSingleThreadExecutor()
    /** Original hex EPCs for Search/Unmatched LED filter (not stripped/item-code variants). */
    private val searchLedEpcs = LinkedHashSet<String>()
    /**
     * Live EPCs that currently match Search (progress/% visible). LED blink is
     * filtered to these only — never the whole unmatched catalog.
     */
    private val foundLedEpcs = LinkedHashMap<String, Long>()
    private val foundLedLock = Any()
    @Volatile private var searchLedPhase = SEARCH_LED_WAIT
    @Volatile private var searchLedApplyBusy = false
    @Volatile private var searchLedCallbackAttached = false
    @Volatile private var searchLedDidDiscover = false
    private var foundLedGatherUntil = 0L
    private var foundLedGatherDeadline = 0L
    private var searchLedAppliedKey = ""
    private var searchLedPhaseUntil = 0L
    /** Tamper-proof EPCs that must stay in EPC mode (LED lock hid their reads). */
    private val searchEpcOnly = HashSet<String>()
    @Volatile private var lastSearchHitAt = 0L
    /** filter = Global LED chips only; all = Unmatched demo Tag LED; epc = Global normal tags. */
    @Volatile private var searchRadioMode = SEARCH_RADIO_EPC
    /** One UART queue — start/stop/LED must not overlap (that fails startInventory). */
    private val uartExecutor = Executors.newSingleThreadExecutor()
    @Volatile private var uartPollPaused = false
    @Volatile private var pollerActive = false
    @Volatile private var pollerParked = true
    private var matchEpcs = HashSet<String>()
    private var inventoryScanMode = false
    private var scanningPermitted = false
    private val inventoryScopeEpcs = HashSet<String>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingTagEvents = ArrayList<String>()
    private val pendingTagLock = Any()
    private var tagFlushScheduled = false
    private val recentEmitAt = HashMap<String, Long>()
    private val recentEmitProx = HashMap<String, Int>()
    private val emitDedupMs = 250L
    /** Search proximity needs fresher RSSI than generic product-scan dedup. Pushpa has none. */
    private val searchEmitDedupMs = 20L
    private val tagFlushDelayMs = 50L

    private fun normalizeScanKey(raw: String): String {
        val t = raw.trim().uppercase()
        if (t.indexOf(' ') < 0 && t.indexOf('\t') < 0) return t
        return t.replace(" ", "").replace("\t", "")
    }

    /** Pushpa Inventoryfragment: strip leading then trailing "00" on reader EPC. */
    private fun stripScanKey00(key: String): String {
        var t = key
        if (t.length > 2 && t.startsWith("00")) {
            t = t.substring(2)
        }
        if (t.length > 2 && t.endsWith("00")) {
            t = t.substring(0, t.length - 2)
        }
        return t
    }

    private fun addSearchKey(raw: String) {
        val key = normalizeScanKey(raw)
        if (key.isEmpty()) return
        synchronized(searchTagLock) {
            fun add(k: String) {
                if (k.isNotEmpty()) searchTags.add(k)
            }
            add(key)
            val stripped = stripScanKey00(key)
            add(stripped)
            if (!key.startsWith("00") && key.length + 2 <= 64) add("00$key")
            if (stripped.isNotEmpty() && stripped != key &&
                !stripped.startsWith("00") && stripped.length + 2 <= 64
            ) {
                add("00$stripped")
            }
            if (key.length > 24) add(key.substring(0, 24))
            if (key.length > 32) add(key.substring(0, 32))
        }
    }

    /** Hex EPCs allowed in Tag LED setFilter (LabelStock chip IDs, not short item codes). */
    private fun isLedFilterHex(key: String): Boolean {
        val n = key.length
        if (n < 8 || n > 64 || n % 2 != 0) return false
        return key.all { ch -> ch in '0'..'9' || ch in 'A'..'F' }
    }

    /** Prefer 96/128-bit EPCs for setFilter; those match the handheld demo. */
    private fun isChipEpcHex(key: String): Boolean {
        if (key.length != 24 && key.length != 32) return false
        return key.all { ch -> ch in '0'..'9' || ch in 'A'..'F' }
    }

    private fun clearSearchTagState() {
        synchronized(searchTagLock) {
            searchTags.clear()
            searchLedEpcs.clear()
        }
        resetSearchLedFoundState()
    }

    private fun resetSearchLedFoundState() {
        synchronized(foundLedLock) {
            foundLedEpcs.clear()
        }
        searchLedPhase = SEARCH_LED_WAIT
        searchLedDidDiscover = false
        foundLedGatherUntil = 0L
        foundLedGatherDeadline = 0L
        searchLedAppliedKey = ""
        searchLedPhaseUntil = 0L
        lastSearchHitAt = 0L
        synchronized(foundLedLock) {
            searchEpcOnly.clear()
        }
    }

    private fun matchesSearchTag(cleanEpc: String): Boolean {
        return resolveSearchEpc(cleanEpc) != null
    }

    /**
     * LED/TID-user inventory can append extra banks after the EPC. Map back to
     * the catalog key so sound + Flutter progress keep matching after LED mode.
     */
    private fun resolveSearchEpc(cleanEpc: String): String? {
        synchronized(searchTagLock) {
            if (searchTags.isEmpty()) return null
            if (searchTags.contains(cleanEpc)) return cleanEpc
            val stripped = stripScanKey00(cleanEpc)
            if (stripped.isNotEmpty() && searchTags.contains(stripped)) return stripped
            fun prefixHit(len: Int): String? {
                if (cleanEpc.length < len) return null
                val p = cleanEpc.substring(0, len)
                if (searchTags.contains(p)) return p
                val s = stripScanKey00(p)
                if (s.isNotEmpty() && searchTags.contains(s)) return s
                return null
            }
            prefixHit(24)?.let { return it }
            prefixHit(32)?.let { return it }
            prefixHit(16)?.let { return it }
            prefixHit(20)?.let { return it }
            // Global Search sends a small key set; live EPCs often have 00-pad
            // that exact contains() misses. Skip this on huge Unmatched catalogs.
            if (searchTags.size <= 400) {
                for (tag in searchTags) {
                    if (tag.length < 8) continue
                    if (cleanEpc.startsWith(tag) || tag.startsWith(cleanEpc)) return tag
                }
            }
            return null
        }
    }

    private var inventoryMediaPlayer: MediaPlayer? = null
    private val sessionUniqueEpcs = HashSet<String>()
    private var reconnectRunnable: Runnable? = null
    @Volatile private var bleConnectQueued = false

    private var trayModeEnabled = false
    private var trayDeviceAddress = ""
    private var r6ModeEnabled = false
    private var r6DeviceAddress = ""
    private var lastR6TriggerMs = 0L
    private var lastScanPower = 5
    private var activeInventorySession = false
    private var soundPoolReady = false

    override fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    override fun onBarcodeHardwareKey() {
        val now = SystemClock.elapsedRealtime()
        if (now - lastBarcodeKeyMs < 300L) return
        lastBarcodeKeyMs = now
        activity.runOnUiThread {
            eventSink?.success("BARCODE_TRIGGER")
        }
        try {
            ensureManagers()
            barcodeManager.startScan()
        } catch (_: Throwable) {
        }
    }

    override fun release() {
        try {
            uartExecutor.submit<Boolean> { stopRfidInventory() }
                .get(3, java.util.concurrent.TimeUnit.SECONDS)
        } catch (_: Throwable) {
            try {
                stopRfidInventory()
            } catch (_: Throwable) {
            }
        }
        if (::trayManager.isInitialized) {
            trayManager.disconnect()
        }
        if (::barcodeManager.isInitialized) {
            barcodeManager.close()
        }
        soundPool?.release()
        soundPool = null
    }

    override fun handleMethod(call: MethodCall, result: MethodChannel.Result) {
        ensureManagers()
        when (call.method) {
            "initReader" -> {
                if (trayModeEnabled || r6ModeEnabled) {
                    result.success(trayManager.isConnected || trayManager.init())
                } else {
                    uartExecutor.execute {
                        val ok = try {
                            uhf().initHardware()
                        } catch (e: Throwable) {
                            Log.e(TAG, "initReader bg failed", e)
                            false
                        }
                        mainHandler.post { result.success(ok) }
                    }
                }
            }
            "prepareForScan" -> {
                scanningPermitted = true
                result.success(true)
            }
            "haltScan" -> {
                haltScan()
                result.success(true)
            }
            "startScanning" -> {
                val power = call.argument<Int>("power") ?: 5
                val inventory = call.argument<Boolean>("inventory") ?: inventoryScanMode
                val playStartSound = call.argument<Boolean>("playStartSound") ?: true
                lastScanPower = power
                if (!inventory) {
                    searchRadioMode = when (call.argument<String>("ledMode")?.trim()?.lowercase()) {
                        "filter" -> SEARCH_RADIO_FILTER
                        "all" -> SEARCH_RADIO_ALL
                        else -> SEARCH_RADIO_EPC
                    }
                }
                // Set before the UART queue runs. A previous stop on that queue
                // used to clear this flag and make Start return false.
                scanningPermitted = true
                uartExecutor.execute {
                    val ok = try {
                        if (r6ModeEnabled) {
                            startR6InventoryGuarded(power, inventory, playStartSound)
                        } else {
                            startRfidInventory(power, inventory, playStartSound)
                        }
                    } catch (e: Throwable) {
                        Log.e(TAG, "startScanning failed", e)
                        false
                    }
                    mainHandler.post { result.success(ok) }
                }
            }
            "stopScanning" -> {
                uartExecutor.execute {
                    val ok = stopRfidInventory()
                    mainHandler.post { result.success(ok) }
                }
            }
            "setPower" -> {
                val power = call.argument<Int>("power") ?: 5
                lastScanPower = power
                uartExecutor.execute {
                    val ok = setReaderPower(power)
                    mainHandler.post { result.success(ok) }
                }
            }
            "isSupported" -> {
                // Optimistic — real init happens on scan. Never call DeviceAPI here.
                result.success(true)
            }
            "setSearchTags" -> {
                val tags = ArrayList(call.argument<List<String>>("tags") ?: emptyList())
                matchEpcs.clear()
                synchronized(searchTagLock) {
                    searchTags.clear()
                    searchLedEpcs.clear()
                }
                resetSearchLedFoundState()
                if (tags.size <= 2500) {
                    for (tag in tags) addSearchKey(tag)
                } else {
                    tagSetExecutor.execute {
                        for (tag in tags) addSearchKey(tag)
                    }
                }
                result.success(true)
            }
            "setSearchLedEpcs" -> {
                val tags = ArrayList(call.argument<List<String>>("tags") ?: emptyList())
                synchronized(searchTagLock) {
                    searchLedEpcs.clear()
                    for (tag in tags) {
                        val key = normalizeScanKey(tag)
                        if (isChipEpcHex(key)) searchLedEpcs.add(key)
                        val stripped = stripScanKey00(key)
                        if (stripped.isNotEmpty() && isChipEpcHex(stripped)) searchLedEpcs.add(stripped)
                    }
                }
                result.success(true)
            }
            "addSearchTags" -> {
                val tags = ArrayList(call.argument<List<String>>("tags") ?: emptyList())
                for (tag in tags) addSearchKey(tag)
                result.success(true)
            }
            "setMatchEpcs" -> {
                val epcs = call.argument<List<String>>("epcs") ?: emptyList()
                clearSearchTagState()
                matchEpcs.clear()
                matchEpcs.addAll(epcs.map { it.trim().uppercase() }.filter { it.isNotEmpty() })
                result.success(true)
            }
            "setInventoryScanMode" -> {
                inventoryScanMode = call.argument<Boolean>("enabled") ?: false
                if (inventoryScanMode) {
                    clearSearchTagState()
                }
                result.success(true)
            }
            "playBeep" -> {
                ensureSoundPool()
                playSound(1, 0)
                result.success(true)
            }
            "playSound" -> {
                ensureSoundPool()
                val id = call.argument<Int>("id") ?: 1
                val loop = call.argument<Int>("loop") ?: 0
                playSound(id, loop)
                result.success(true)
            }
            "stopSound" -> {
                val id = call.argument<Int>("id")
                if (id != null) {
                    stopSound(id)
                } else {
                    stopAllSounds()
                }
                result.success(true)
            }
            "startInventorySound" -> {
                ensureSoundPool()
                startInventoryLoopSound()
                result.success(true)
            }
            "stopInventorySound" -> {
                stopInventoryLoopSound()
                result.success(true)
            }
            "clearMatchEpcs" -> {
                matchEpcs.clear()
                result.success(true)
            }
            "clearSearchTags" -> {
                clearSearchTagState()
                stopAllSounds()
                lastSearchSoundId = -1
                result.success(true)
            }
            "clearInventoryScope" -> {
                inventoryScopeEpcs.clear()
                result.success(true)
            }
            "setInventoryScopeEpcs" -> {
                val epcs = call.argument<List<String>>("epcs") ?: emptyList()
                inventoryScopeEpcs.clear()
                for (epc in epcs) {
                    val key = epc.trim().uppercase()
                    if (key.isNotEmpty()) {
                        inventoryScopeEpcs.add(key)
                    }
                }
                result.success(true)
            }
            "addInventoryScopeEpcs" -> {
                val epcs = call.argument<List<String>>("epcs") ?: emptyList()
                for (epc in epcs) {
                    val key = epc.trim().uppercase()
                    if (key.isNotEmpty()) {
                        inventoryScopeEpcs.add(key)
                    }
                }
                result.success(true)
            }
            "setTrayMode" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val address = call.argument<String>("address")?.trim().orEmpty()
                if (enabled) {
                    r6ModeEnabled = false
                    r6DeviceAddress = ""
                }
                trayModeEnabled = enabled
                trayDeviceAddress = address
                applyBleReaderMode()
                result.success(trayStatusMap())
            }
            "setR6Mode" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val address = call.argument<String>("address")?.trim().orEmpty()
                if (enabled) {
                    ensureBluetoothPermissions()
                    trayModeEnabled = false
                    trayDeviceAddress = ""
                }
                r6ModeEnabled = enabled
                r6DeviceAddress = address
                applyBleReaderMode()
                result.success(r6StatusMap())
            }
            "listBondedBluetoothDevices" -> {
                Executors.newSingleThreadExecutor().execute {
                    val list = try {
                        if (!hasBluetoothPermission()) {
                            emptyList()
                        } else {
                            trayManager.scanNearbyDevices(4500)
                        }
                    } catch (e: Throwable) {
                        e.printStackTrace()
                        emptyList()
                    }
                    mainHandler.post {
                        result.success(list)
                    }
                }
            }
            "listSystemConnectedBluetoothDevices" -> {
                result.success(listSystemConnectedBluetoothDevices())
            }
            "getTrayStatus" -> result.success(trayStatusMap())
            "getR6Status" -> result.success(r6StatusMap())
            "openBarcode" -> result.success(barcodeManager.openIfNeeded())
            "startBarcodeScan" -> result.success(barcodeManager.startScan())
            "stopBarcodeScan" -> {
                barcodeManager.stopScan()
                result.success(true)
            }
            "closeBarcode" -> {
                barcodeManager.close()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun uhf(): UhfFacade {
        val existing = uhfFacade
        if (existing != null) return existing
        // Reflection keeps UART DeviceAPI out of this class's eager linkage where possible.
        val clazz = Class.forName("com.loyalstring.rfid.rfid_flutter.UhfUartFacadeImpl")
        val inst = clazz.getConstructor(android.content.Context::class.java)
            .newInstance(activity) as UhfFacade
        uhfFacade = inst
        return inst
    }

    private fun ensureManagers() {
        if (!::barcodeManager.isInitialized) {
            barcodeManager = BarcodeManager(activity)
            barcodeManager.setOnScanned { data ->
                activity.runOnUiThread {
                    eventSink?.success("BARCODE:$data")
                }
            }
        }
        if (!::trayManager.isInitialized) {
            trayManager = TrayReaderManager(
                activity,
                onTagRead = { epc, rssi ->
                    if (isScanning) {
                        handleTagRead(epc, rssi, activeInventorySession)
                        // Inventory scan (Scan Display) beeps on match in Flutter — not per tag.
                        if (r6ModeEnabled && !activeInventorySession) {
                            try {
                                trayManager.triggerBeep(40)
                            } catch (_: Throwable) {
                            }
                        }
                    }
                },
                onConnectionChange = { connected, _ ->
                    mainHandler.post {
                        val event = when {
                            trayModeEnabled -> if (connected) "TRAY_CONNECTED" else "TRAY_DISCONNECTED"
                            r6ModeEnabled -> if (connected) "R6_CONNECTED" else "R6_DISCONNECTED"
                            else -> if (connected) "TRAY_CONNECTED" else "TRAY_DISCONNECTED"
                        }
                        eventSink?.success(event)
                        if (connected) {
                            cancelBleReconnect()
                        } else if (!trayManager.isConnecting) {
                            scheduleBleReconnectIfNeeded()
                        }
                    }
                },
                onKeyEvent = { down, keyCode ->
                    if (r6ModeEnabled) {
                        handleR6SledTrigger(down, keyCode)
                    }
                },
            )
        }
    }

    private fun setReaderPower(power: Int): Boolean {
        lastScanPower = power
        return try {
            if (useBleReader()) {
                trayManager.setPower(power)
            } else {
                uhf().setPower(power)
            }
        } catch (_: Throwable) {
            false
        }
    }

    private fun useBleReader(): Boolean {
        return (trayModeEnabled || r6ModeEnabled) &&
            ::trayManager.isInitialized &&
            (trayManager.isReallyConnected() || trayManager.isConnected)
    }

    private fun applyBleReaderMode() {
        val enabled = trayModeEnabled || r6ModeEnabled
        val address = when {
            trayModeEnabled -> trayDeviceAddress
            r6ModeEnabled -> r6DeviceAddress
            else -> ""
        }
        cancelBleReconnect()
        if (enabled && address.isNotEmpty()) {
            if (!::trayManager.isInitialized) {
                ensureManagers()
            }
            if (trayManager.isReallyConnected()) {
                Log.i(TAG, "BLE already linked — skip reconnect")
                return
            }
            if (trayManager.isConnecting || bleConnectQueued) {
                Log.i(TAG, "BLE connect already in progress — skip")
                return
            }
            bleConnectQueued = true
            Executors.newSingleThreadExecutor().execute {
                try {
                    trayManager.connectAndWait(address, 28000L)
                } finally {
                    bleConnectQueued = false
                }
            }
        } else {
            bleConnectQueued = false
            if (::trayManager.isInitialized) {
                trayManager.disconnect()
            }
        }
    }

    private fun scheduleBleReconnectIfNeeded() {
        val address = when {
            trayModeEnabled -> trayDeviceAddress
            r6ModeEnabled -> r6DeviceAddress
            else -> ""
        }
        if (address.isEmpty() || (!trayModeEnabled && !r6ModeEnabled)) return
        if (trayManager.isConnecting || bleConnectQueued || trayManager.isReallyConnected()) return
        cancelBleReconnect()
        val runnable = Runnable {
            if ((trayModeEnabled || r6ModeEnabled) &&
                !trayManager.isReallyConnected() &&
                !trayManager.isConnecting &&
                !bleConnectQueued &&
                address.isNotEmpty()
            ) {
                bleConnectQueued = true
                Executors.newSingleThreadExecutor().execute {
                    try {
                        trayManager.connectAndWait(address, 28000L)
                    } finally {
                        bleConnectQueued = false
                    }
                }
            }
        }
        reconnectRunnable = runnable
        mainHandler.postDelayed(runnable, 5000L)
    }

    private fun cancelBleReconnect() {
        reconnectRunnable?.let { mainHandler.removeCallbacks(it) }
        reconnectRunnable = null
    }

    private fun trayStatusMap(): HashMap<String, Any> {
        val map = HashMap<String, Any>()
        val linked = ::trayManager.isInitialized &&
            (trayManager.isReallyConnected() || trayManager.isConnected)
        map["enabled"] = trayModeEnabled
        map["connected"] = trayModeEnabled && linked
        map["connecting"] = trayModeEnabled && ::trayManager.isInitialized &&
            (trayManager.isConnecting || bleConnectQueued)
        map["address"] = trayDeviceAddress
        return map
    }

    private fun r6StatusMap(): HashMap<String, Any> {
        val map = HashMap<String, Any>()
        map["enabled"] = r6ModeEnabled
        map["connected"] = r6ModeEnabled && (trayManager.isReallyConnected() || trayManager.isConnected)
        map["address"] = r6DeviceAddress
        map["connecting"] = r6ModeEnabled && (trayManager.isConnecting || bleConnectQueued)
        return map
    }

    private fun handleR6SledTrigger(down: Boolean, keyCode: Int) {
        if (!down) return
        val now = SystemClock.elapsedRealtime()
        if (now - lastR6TriggerMs < 300L) return
        lastR6TriggerMs = now

        val connected = trayManager.isReallyConnected() || trayManager.isConnected
        Log.i(TAG, "R6 sled trigger keyCode=$keyCode scanning=$isScanning connected=$connected")

        mainHandler.post {
            eventSink?.success("TRIGGER_CLICK")
        }

        if (!isScanning) {
            scanningPermitted = true
            uartExecutor.execute {
                val ok = startR6InventoryGuarded(lastScanPower, inventoryScanMode)
                Log.i(TAG, "R6 keyDown native startInventory=$ok")
                if (!ok) {
                    trayManager.bindKeyCallbackNow()
                }
            }
        }
    }

    /** Devices already linked in Android Bluetooth settings — no in-app scan/pair. */
    private fun listSystemConnectedBluetoothDevices(): List<Map<String, String>> {
        if (!hasBluetoothConnectPermission()) return emptyList()
        val found = LinkedHashMap<String, String>()
        try {
            val mgr = activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            if (mgr != null) {
                try {
                    for (device in mgr.getConnectedDevices(BluetoothProfile.GATT)) {
                        addConnectedBtDevice(found, device)
                    }
                } catch (e: Throwable) {
                    Log.w(TAG, "GATT connected list failed", e)
                }
                try {
                    for (device in mgr.getConnectedDevices(BluetoothProfile.GATT_SERVER)) {
                        addConnectedBtDevice(found, device)
                    }
                } catch (_: Throwable) {
                }
            }
            @Suppress("DEPRECATION")
            val adapter = BluetoothAdapter.getDefaultAdapter()
            if (adapter != null && adapter.isEnabled) {
                for (device in adapter.bondedDevices.orEmpty()) {
                    if (isBluetoothDeviceConnected(device)) {
                        addConnectedBtDevice(found, device)
                    }
                }
            }
        } catch (e: Throwable) {
            Log.e(TAG, "listSystemConnectedBluetoothDevices", e)
        }
        return found.map { (address, name) ->
            mapOf("name" to name, "address" to address)
        }
    }

    private fun addConnectedBtDevice(found: LinkedHashMap<String, String>, device: BluetoothDevice) {
        val address = device.address?.trim().orEmpty()
        if (address.isEmpty()) return
        val name = try {
            device.name?.trim()?.takeIf { it.isNotEmpty() }
        } catch (_: SecurityException) {
            null
        } ?: "Bluetooth Device"
        val existing = found[address]
        if (existing.isNullOrBlank() || existing == "Bluetooth Device") {
            found[address] = name
        }
    }

    private fun isBluetoothDeviceConnected(device: BluetoothDevice): Boolean {
        return try {
            val method = device.javaClass.getMethod("isConnected")
            method.invoke(device) as? Boolean ?: false
        } catch (_: Throwable) {
            false
        }
    }

    private fun hasBluetoothConnectPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(activity, Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            @Suppress("DEPRECATION")
            ContextCompat.checkSelfPermission(activity, Manifest.permission.BLUETOOTH) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    private fun hasBluetoothPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val connect = ContextCompat.checkSelfPermission(activity, Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED
            val scan = ContextCompat.checkSelfPermission(activity, Manifest.permission.BLUETOOTH_SCAN) ==
                PackageManager.PERMISSION_GRANTED
            connect && scan
        } else {
            @Suppress("DEPRECATION")
            val bt = ContextCompat.checkSelfPermission(activity, Manifest.permission.BLUETOOTH) ==
                PackageManager.PERMISSION_GRANTED
            val loc = ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
            bt && loc
        }
    }

    private fun ensureBluetoothPermissions() {
        if (hasBluetoothPermission()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.ACCESS_FINE_LOCATION,
                ),
                2401,
            )
        } else {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(
                    Manifest.permission.BLUETOOTH,
                    Manifest.permission.BLUETOOTH_ADMIN,
                    Manifest.permission.ACCESS_FINE_LOCATION,
                ),
                2401,
            )
        }
    }

    private fun haltScan() {
        scanningPermitted = false
        inventoryScanMode = false
        inventoryScopeEpcs.clear()
        sessionUniqueEpcs.clear()
        stopInventoryLoopSound()
    }

    private fun startRfidInventory(power: Int, inventory: Boolean, playStartSound: Boolean = true): Boolean {
        scanningPermitted = true
        lastScanPower = power
        if (isScanning) {
            // Leftover LED/inventory session would keep an old EPC filter and
            // miss the new Global Search item. Restart Search at the requested power.
            if (trayModeEnabled || r6ModeEnabled) {
                if (trayManager.isReallyConnected() && pollerActive) {
                    return true
                }
                Log.w(TAG, "Stale BLE isScanning — restart inventory")
                isScanning = false
                stopPollingThread()
            } else if (!inventory) {
                stopRfidInventory()
            } else {
                return true
            }
        }
        activeInventorySession = inventory
        sessionUniqueEpcs.clear()
        if (trayModeEnabled || r6ModeEnabled) {
            if (r6ModeEnabled) {
                return startR6InventoryGuarded(power, inventory, playStartSound)
            }
            if (!trayManager.isReallyConnected()) {
                val address = trayDeviceAddress.trim()
                if (address.isEmpty()) {
                    Log.e(TAG, "Tray mode on but no device address")
                    return false
                }
                val linked = trayManager.connectAndWait(address, 28000L)
                if (!linked && !trayManager.isOsLinked(address)) {
                    Log.e(TAG, "Tray connectAndWait failed for $address")
                    return false
                }
            }
            return startTrayInventory(power, inventory, playStartSound)
        }
        return try {
            ensureSoundPool()
            if (!uhf().initHardware()) {
                Log.e(TAG, "startRfidInventory: initHardware failed")
                stopInventoryLoopSound()
                return false
            }
            applySearchLedBlinkModeIfNeeded(inventory)
            clearSearchLedTagCallback()
            if (inventory) {
                uhf().prepareScan(power)
                startInventoryLoopSound()
            } else {
                // Stop leftover inventory so LED Tag mode + filter apply cleanly.
                try {
                    uhf().stopInventory()
                } catch (_: Throwable) {
                }
                try {
                    Thread.sleep(80L)
                } catch (_: InterruptedException) {
                }
                prepareSearchRadio(power)
                // Accept callback tags immediately. LED chips often arrive on
                // setInventoryCallback before the poller thread is up.
                isScanning = true
                attachSearchLedTagCallback()
                if (playStartSound) playSound(1, 0)
            }
            var started = uhf().startInventory()
            Log.i(TAG, "startInventory attempt=1 => $started")
            if (!started) {
                try {
                    uhf().stopInventory()
                } catch (_: Throwable) {
                }
                try {
                    Thread.sleep(150L)
                } catch (_: InterruptedException) {
                }
                if (inventory) {
                    uhf().prepareScan(power)
                } else {
                    prepareSearchRadio(power)
                    attachSearchLedTagCallback()
                }
                started = uhf().startInventory()
                Log.i(TAG, "startInventory attempt=2 => $started")
            }
            if (!started) {
                Log.w(TAG, "startInventory failed — recoverHardware")
                if (uhf().recoverHardware()) {
                    if (inventory) {
                        uhf().prepareScan(power)
                    } else {
                        prepareSearchRadio(power)
                        attachSearchLedTagCallback()
                    }
                    started = uhf().startInventory()
                    Log.i(TAG, "startInventory attempt=3 recover => $started")
                }
            }
            if (started) {
                isScanning = true
                startPollingThread(inventory, useTray = false)
            } else {
                isScanning = false
                clearSearchLedTagCallback()
                stopInventoryLoopSound()
            }
            started
        } catch (e: Throwable) {
            e.printStackTrace()
            isScanning = false
            stopInventoryLoopSound()
            false
        }
    }

    private fun startR6InventoryGuarded(power: Int, inventory: Boolean, playStartSound: Boolean = true): Boolean {
        scanningPermitted = true
        if (isScanning) {
            if (trayManager.isReallyConnected() && pollerActive) {
                return true
            }
            Log.w(TAG, "Stale R6 isScanning — restart inventory")
            isScanning = false
            stopPollingThread()
        }
        if (!r6ModeEnabled) {
            return false
        }
        val address = r6DeviceAddress.trim()
        if (address.isEmpty()) {
            return false
        }
        if (!trayManager.isReallyConnected()) {
            val linked = trayManager.connectAndWait(address, 28000L)
            if (!linked && !trayManager.isOsLinked(address)) {
                Log.e(TAG, "R6 connectAndWait failed for $address")
                return false
            }
        }
        activeInventorySession = inventory
        sessionUniqueEpcs.clear()
        trayManager.bindKeyCallbackNow()
        return startR6Inventory(power, inventory, playStartSound)
    }

    private fun startTrayInventory(power: Int, inventory: Boolean, playStartSound: Boolean = true): Boolean {
        return try {
            ensureSoundPool()
            try {
                trayManager.setPower(power)
            } catch (_: Throwable) {
            }
            // GATT often needs a brief settle before startInventoryTag succeeds.
            try {
                Thread.sleep(600L)
            } catch (_: InterruptedException) {
            }
            trayManager.drainBuffer()
            if (inventory) {
                startInventoryLoopSound()
            } else if (playStartSound) {
                playSound(1, 0)
            }
            var started = false
            for (attempt in 0 until 3) {
                if (attempt > 0) {
                    try {
                        trayManager.stopInventory()
                    } catch (_: Throwable) {
                    }
                    try {
                        Thread.sleep(250L * attempt)
                    } catch (_: InterruptedException) {
                    }
                    trayManager.drainBuffer()
                }
                started = trayManager.startInventory()
                Log.i(TAG, "Tray startInventory attempt=${attempt + 1} => $started")
                if (started) break
            }
            if (!started) {
                val address = trayDeviceAddress.trim()
                if (address.isNotEmpty()) {
                    if (trayManager.isOsLinked(address) || trayManager.isReallyConnected()) {
                        Log.w(TAG, "Tray startInventory failed — retry without cancelOpen")
                        try {
                            Thread.sleep(600L)
                        } catch (_: InterruptedException) {
                        }
                        trayManager.drainBuffer()
                        started = trayManager.startInventory()
                        Log.i(TAG, "Tray startInventory OS-held retry => $started")
                    } else {
                        Log.w(TAG, "Tray startInventory failed — one reconnect retry")
                        val linked = trayManager.connectAndWait(address, 18000L)
                        if (linked) {
                            try {
                                Thread.sleep(500L)
                            } catch (_: InterruptedException) {
                            }
                            trayManager.drainBuffer()
                            started = trayManager.startInventory()
                            Log.i(TAG, "Tray startInventory after reconnect => $started")
                        }
                    }
                }
            }
            if (started) {
                isScanning = true
                startPollingThread(inventory, useTray = true)
            } else {
                isScanning = false
                stopInventoryLoopSound()
            }
            started
        } catch (e: Throwable) {
            e.printStackTrace()
            isScanning = false
            stopInventoryLoopSound()
            false
        }
    }

    private fun startR6Inventory(power: Int, inventory: Boolean, playStartSound: Boolean = true): Boolean {
        return try {
            ensureSoundPool()
            try {
                trayManager.setPower(power)
            } catch (_: Throwable) {
            }
            try {
                Thread.sleep(400L)
            } catch (_: InterruptedException) {
            }
            trayManager.drainBuffer()
            if (inventory) {
                startInventoryLoopSound()
            } else if (playStartSound) {
                playSound(1, 0)
            }
            var started = false
            for (attempt in 0 until 3) {
                if (attempt > 0) {
                    try {
                        trayManager.stopInventory()
                    } catch (_: Throwable) {
                    }
                    try {
                        Thread.sleep(200L * attempt)
                    } catch (_: InterruptedException) {
                    }
                    trayManager.drainBuffer()
                }
                started = trayManager.startInventory()
                Log.i(TAG, "R6 startInventory attempt=${attempt + 1} => $started")
                if (started) break
            }
            if (!started) {
                val address = r6DeviceAddress.trim()
                if (address.isNotEmpty()) {
                    if (trayManager.isOsLinked(address) || trayManager.isReallyConnected()) {
                        Log.w(TAG, "R6 startInventory failed — retry without cancelOpen")
                        try {
                            Thread.sleep(500L)
                        } catch (_: InterruptedException) {
                        }
                        trayManager.drainBuffer()
                        started = trayManager.startInventory()
                        Log.i(TAG, "R6 startInventory OS-held retry => $started")
                    } else {
                        Log.w(TAG, "R6 startInventory failed — one reconnect retry")
                        val linked = trayManager.connectAndWait(address, 18000L)
                        if (linked) {
                            try {
                                Thread.sleep(500L)
                            } catch (_: InterruptedException) {
                            }
                            trayManager.drainBuffer()
                            started = trayManager.startInventory()
                            Log.i(TAG, "R6 startInventory after reconnect => $started")
                        }
                    }
                }
            }
            if (started) {
                isScanning = true
                startPollingThread(inventory, useTray = true)
            } else {
                isScanning = false
                stopInventoryLoopSound()
            }
            started
        } catch (e: Throwable) {
            e.printStackTrace()
            isScanning = false
            stopInventoryLoopSound()
            false
        }
    }

    /**
     * Search never starts in unfiltered LED Tag mode (that lights every LED).
     */
    private fun applySearchLedBlinkModeIfNeeded(inventory: Boolean) {
        if (inventory || trayModeEnabled || r6ModeEnabled) return
        resetSearchLedFoundState()
    }

    /** Unique 24/32 LabelStock EPCs for Tag LED setFilter (max 8). */
    private fun catalogChipEpcs(): List<String> {
        synchronized(searchTagLock) {
            val chip = LinkedHashSet<String>()
            for (epc in searchLedEpcs) {
                if (isChipEpcHex(epc)) chip.add(epc)
                if (chip.size >= SEARCH_LED_MAX) break
            }
            return ArrayList(chip)
        }
    }

    private fun uniqueLedCatalogCount(): Int {
        synchronized(searchTagLock) {
            val chip = LinkedHashSet<String>()
            for (epc in searchLedEpcs) {
                if (isChipEpcHex(epc)) chip.add(epc)
            }
            return chip.size
        }
    }

    private fun isSmallLabelStockLedList(): Boolean {
        val n = uniqueLedCatalogCount()
        return n in 1..SEARCH_LED_MAX
    }

    /**
     * EPCs allowed to blink: LabelStock only.
     * Small Global Search: catalog EPCs (unused LEDs stay dark).
     * Large Unmatched: live found matches from that screen only.
     */
    private fun blinkEpcsForLabelStock(): List<String> {
        val catalog = catalogChipEpcs()
        val found = synchronized(foundLedLock) { ArrayList(foundLedEpcs.keys) }
        if (isSmallLabelStockLedList()) {
            if (found.isEmpty()) return catalog
            val unique = LinkedHashSet<String>()
            unique.addAll(found)
            for (epc in catalog) {
                if (unique.size >= SEARCH_LED_MAX) break
                unique.add(epc)
            }
            return ArrayList(unique)
        }
        return found
    }

    /**
     * Extra 00-prefix / strip variants so setFilter matches the live chip EPC.
     * Prefer 24/32-bit IDs; max 8 on the radio.
     */
    private fun expandLedFilterEpcs(epcs: List<String>): List<String> {
        val chip = LinkedHashSet<String>()
        val extra = LinkedHashSet<String>()
        fun consider(raw: String) {
            val epc = normalizeScanKey(raw)
            if (!isLedFilterHex(epc)) return
            if (isChipEpcHex(epc)) chip.add(epc) else extra.add(epc)
            val stripped = stripScanKey00(epc)
            if (isChipEpcHex(stripped)) chip.add(stripped)
            else if (isLedFilterHex(stripped)) extra.add(stripped)
            if (!epc.startsWith("00") && epc.length + 2 <= 32) {
                val padded = "00$epc"
                if (isChipEpcHex(padded)) chip.add(padded)
                else if (isLedFilterHex(padded)) extra.add(padded)
            }
        }
        for (epc in epcs) consider(epc)
        val unique = LinkedHashSet<String>()
        unique.addAll(chip)
        if (unique.size < SEARCH_LED_MAX) {
            for (epc in extra) {
                unique.add(epc)
                if (unique.size >= SEARCH_LED_MAX) break
            }
        }
        return ArrayList(unique.take(SEARCH_LED_MAX))
    }

    /**
     * Unmatched: demo Tag LED Inventory Solid, no filter (LED + normal scan).
     * Global: same Solid mode with checked searched EPCs so unsearched LEDs stay
     * dark. Empty catalog = EPC-only (no LED chip on that search).
     */
    private fun prepareSearchRadio(power: Int) {
        uhf().setPower(power)
        if (searchRadioMode == SEARCH_RADIO_ALL) {
            val ok = uhf().applyLedBlinkInventoryNoFilter()
            Log.i(TAG, "Unmatched Tag LED Inventory Solid (LED+normal) => $ok")
            if (!ok) {
                uhf().prepareScan(power)
            }
            searchLedAppliedKey = ""
            searchLedPhase = if (ok) SEARCH_LED_DISCOVER else SEARCH_LED_WAIT
            searchLedPhaseUntil = 0L
            foundLedGatherUntil = 0L
            foundLedGatherDeadline = 0L
            return
        }
        // EPC-only first: tamper-proof tags get % / sound and extra LEDs stay dark.
        // After a search hit, tick applies Tag LED + strict offset-32 filter to
        // that live chip only. If reads stop, revert to EPC (tamper-proof).
        uhf().prepareScan(power)
        searchLedAppliedKey = ""
        searchLedPhase = SEARCH_LED_DISCOVER
        searchLedPhaseUntil = 0L
        foundLedGatherUntil = 0L
        foundLedGatherDeadline = 0L
        lastSearchHitAt = 0L
    }

    private fun searchLedKey(epcs: Collection<String>): String =
        epcs.sorted().joinToString(",")

    /** Live 24/32 chip EPC for Tag LED setFilter. Loose hex matches light other tags. */
    private fun ledEpcOf(cleanEpc: String): String? {
        if (resolveSearchEpc(cleanEpc) == null) return null
        if (isChipEpcHex(cleanEpc)) return cleanEpc
        if (cleanEpc.length > 32) {
            val p32 = cleanEpc.substring(0, 32)
            if (isChipEpcHex(p32) && matchesSearchTag(p32)) return p32
        }
        if (cleanEpc.length > 24) {
            val p24 = cleanEpc.substring(0, 24)
            if (isChipEpcHex(p24) && matchesSearchTag(p24)) return p24
        }
        val resolved = resolveSearchEpc(cleanEpc) ?: return null
        return if (isChipEpcHex(resolved)) resolved else null
    }

    /** When a search tag is matched (progress/%), queue that live chip EPC for LED. */
    private fun noteFoundSearchLed(cleanEpc: String) {
        if (activeInventorySession || trayModeEnabled || r6ModeEnabled) return
        val epc = ledEpcOf(cleanEpc) ?: return
        val now = SystemClock.elapsedRealtime()
        synchronized(foundLedLock) {
            if (searchEpcOnly.contains(epc)) return
            val isNew = !foundLedEpcs.containsKey(epc)
            foundLedEpcs[epc] = now
            while (foundLedEpcs.size > SEARCH_LED_MAX) {
                val oldest = foundLedEpcs.keys.first()
                foundLedEpcs.remove(oldest)
            }
            if (isNew) {
                foundLedGatherUntil = now + SEARCH_LED_GATHER_MS
                if (foundLedGatherDeadline == 0L) {
                    foundLedGatherDeadline = now + SEARCH_LED_GATHER_MAX_MS
                }
            }
        }
    }

    private fun tickSearchLedBlink() {
        // Unmatched stays unfiltered Tag LED for the whole scan.
        if (searchRadioMode != SEARCH_RADIO_FILTER) return
        if (searchLedApplyBusy || uartPollPaused) return
        if (!isScanning || activeInventorySession || trayModeEnabled || r6ModeEnabled) return
        val now = SystemClock.elapsedRealtime()
        if (searchLedPhase == SEARCH_LED_BLINK && lastSearchHitAt > 0L &&
            now - lastSearchHitAt > SEARCH_LED_HIT_TIMEOUT_MS
        ) {
            requestGlobalEpcRevert()
            return
        }
        val found = synchronized(foundLedLock) {
            foundLedEpcs.keys.filter { it !in searchEpcOnly }
        }
        if (found.isEmpty()) return
        if (searchLedKey(found) == searchLedAppliedKey) return
        var wantLock = false
        synchronized(foundLedLock) {
            if (foundLedGatherUntil <= 0L) {
                wantLock = true
            } else {
                wantLock = now >= foundLedGatherUntil ||
                    (foundLedGatherDeadline > 0L && now >= foundLedGatherDeadline)
            }
        }
        if (wantLock) requestSearchLedHandoff(found)
    }

    private fun requestGlobalEpcRevert() {
        if (searchLedApplyBusy) return
        searchLedApplyBusy = true
        uartExecutor.execute {
            try {
                revertGlobalSearchToEpc()
            } finally {
                uartPollPaused = false
                searchLedApplyBusy = false
            }
        }
    }

    /**
     * Tamper-proof tags go quiet in Tag LED mode. Return Global Search to EPC
     * so % / sound continue, and do not retry LED lock on those EPCs.
     */
    private fun revertGlobalSearchToEpc() {
        if (!isScanning || searchRadioMode != SEARCH_RADIO_FILTER) return
        if (!pollerActive || !waitUntilPollerParked(400L)) {
            uartPollPaused = false
            return
        }
        val locked = synchronized(foundLedLock) { ArrayList(foundLedEpcs.keys) }
        synchronized(foundLedLock) {
            searchEpcOnly.addAll(locked)
        }
        try {
            uhf().stopInventory()
            try {
                Thread.sleep(80L)
            } catch (_: InterruptedException) {
            }
            if (!isScanning) return
            uhf().prepareScan(lastScanPower)
            attachSearchLedTagCallback()
            uhf().startInventory()
            searchLedAppliedKey = ""
            searchLedPhase = SEARCH_LED_DISCOVER
            lastSearchHitAt = SystemClock.elapsedRealtime()
            Log.i(TAG, "Global Search reverted to EPC (tamper-proof) epcs=${locked.size}")
        } catch (e: Throwable) {
            Log.w(TAG, "Global EPC revert failed: ${e.message}")
            try {
                if (isScanning) {
                    attachSearchLedTagCallback()
                    resumeSearchInventoryRunning()
                }
            } catch (_: Throwable) {
            }
        }
    }

    private fun requestSearchLedHandoff(epcs: List<String>) {
        if (epcs.isEmpty() || searchLedApplyBusy) return
        if (searchLedKey(epcs) == searchLedAppliedKey) return
        searchLedApplyBusy = true
        uartExecutor.execute {
            try {
                applySearchLedHandoff(epcs)
            } finally {
                uartPollPaused = false
                searchLedApplyBusy = false
            }
        }
    }

    private fun requestSearchLedDiscover() {
        if (searchLedApplyBusy) return
        if (activeInventorySession || trayModeEnabled || r6ModeEnabled) return
        searchLedApplyBusy = true
        uartExecutor.execute {
            try {
                applySearchEpcScanWindow()
            } finally {
                uartPollPaused = false
                searchLedApplyBusy = false
            }
        }
    }

    /**
     * Do not switch Search to EPC-only mid-scan. setEPCMode turns the LED off
     * and stopInventory drops the session.
     */
    private fun applySearchEpcScanWindow() {
        resumeSearchInventoryRunning()
    }

    private fun resumeSearchEpcModeLocked() {
        uhf().prepareScan(lastScanPower)
        attachSearchLedTagCallback()
        var started = uhf().startInventory()
        if (!started && isScanning) {
            try {
                Thread.sleep(50L)
            } catch (_: InterruptedException) {
            }
            started = uhf().startInventory()
        }
        val now = SystemClock.elapsedRealtime()
        searchLedAppliedKey = ""
        searchLedPhase = SEARCH_LED_DISCOVER
        searchLedPhaseUntil = now + SEARCH_LED_SCAN_MS
        foundLedGatherUntil = now + SEARCH_LED_GATHER_MS
        foundLedGatherDeadline = now + SEARCH_LED_SCAN_MS
    }

    /**
     * Demo Tag LED Inventory delivers tags on [UhfFacade.setInventoryCallback],
     * not readTagFromBuffer. Keep RSSI/sound/progress alive after LED blink mode.
     */
    private fun attachSearchLedTagCallback() {
        try {
            uhf().setInventoryCallback { epc, rssi ->
                if (!scanningPermitted) return@setInventoryCallback
                val cleanEpc = normalizeScanKey(epc)
                if (cleanEpc.isEmpty()) return@setInventoryCallback
                handleTagRead(cleanEpc, rssi, inventory = false)
            }
            searchLedCallbackAttached = true
        } catch (e: Throwable) {
            searchLedCallbackAttached = false
            Log.w(TAG, "Search LED tag callback failed: ${e.message}")
        }
    }

    private fun clearSearchLedTagCallback() {
        searchLedCallbackAttached = false
        try {
            uhfFacade?.setInventoryCallback(null)
        } catch (_: Throwable) {
        }
    }

    /**
     * Unmatched first pass: lock Solid to found search EPCs so extras go dark.
     * Do not stopInventory — that turns every LED off and can leave scanning dead.
     * Park the poller only so setFilter does not overlap readTagFromBuffer.
     * Callback tags (progress/sound) keep flowing. Then startInventory in case
     * the reader dropped the session when the filter was applied.
     */
    private fun applySearchLedHandoff(epcs: List<String>) {
        if (!isScanning || activeInventorySession || trayModeEnabled || r6ModeEnabled) return
        if (epcs.isEmpty()) return
        if (searchLedPhase == SEARCH_LED_BLINK && searchLedKey(epcs) == searchLedAppliedKey) return
        if (!pollerActive || !waitUntilPollerParked(400L)) {
            uartPollPaused = false
            searchLedFailBackoff()
            return
        }
        try {
            if (!isScanning) return
            val filtered = uhf().applyLedTagBlinkMode(epcs)
            Log.i(TAG, "Search LED live filter epcs=${epcs.size} => $filtered")
            attachSearchLedTagCallback()
            resumeSearchInventoryRunning()
            if (filtered && isScanning) {
                searchLedAppliedKey = searchLedKey(epcs)
                searchLedPhase = SEARCH_LED_BLINK
                searchLedDidDiscover = false
                searchLedPhaseUntil = 0L
                foundLedGatherUntil = 0L
                foundLedGatherDeadline = 0L
            } else {
                searchLedFailBackoff()
            }
        } catch (e: Throwable) {
            Log.w(TAG, "Search LED live filter failed: ${e.message}")
            try {
                attachSearchLedTagCallback()
                resumeSearchInventoryRunning()
            } catch (_: Throwable) {
            }
            searchLedFailBackoff()
        }
    }

    /** startInventoryTag is a no-op if already running; restarts if the session dropped. */
    private fun resumeSearchInventoryRunning() {
        if (!isScanning) return
        if (uhf().startInventory()) return
        try {
            Thread.sleep(80L)
        } catch (_: InterruptedException) {
        }
        if (!isScanning) return
        uhf().startInventory()
    }

    private fun waitUntilPollerParked(timeoutMs: Long): Boolean {
        uartPollPaused = true
        val t0 = SystemClock.elapsedRealtime()
        while (!pollerParked && SystemClock.elapsedRealtime() - t0 < timeoutMs) {
            try {
                Thread.sleep(10L)
            } catch (_: InterruptedException) {
                break
            }
        }
        return pollerParked
    }

    private fun searchLedFailBackoff() {
        foundLedGatherUntil = SystemClock.elapsedRealtime() + 2000L
        foundLedGatherDeadline = foundLedGatherUntil
    }

    private fun stopUartInventoryNow(useBle: Boolean) {
        for (attempt in 0 until 3) {
            var stopped = false
            try {
                stopped = if (useBle) {
                    if (::trayManager.isInitialized) trayManager.stopInventory() else true
                } else {
                    uhfFacade?.stopInventory() ?: true
                }
            } catch (_: Throwable) {
            }
            if (stopped) break
            try {
                Thread.sleep(50L)
            } catch (_: InterruptedException) {
            }
        }
        if (!useBle) {
            try {
                uhfFacade?.restoreEpcInventoryMode()
            } catch (_: Throwable) {
            }
        }
    }

    private fun stopRfidInventory(): Boolean {
        inventoryScanMode = false
        inventoryScopeEpcs.clear()
        sessionUniqueEpcs.clear()
        resetSearchLedFoundState()
        stopAllSounds()
        lastSearchSoundId = -1
        lastCloseSearchSoundAt = 0L
        stopInventoryLoopSound()

        isScanning = false
        activeInventorySession = false
        uartPollPaused = true
        searchLedApplyBusy = false
        stopPollingThread()
        synchronized(pendingTagLock) {
            pendingTagEvents.clear()
            tagFlushScheduled = false
        }
        synchronized(recentEmitAt) {
            recentEmitAt.clear()
        }
        synchronized(recentEmitProx) {
            recentEmitProx.clear()
        }
        clearSearchLedTagCallback()
        stopUartInventoryNow(useBleReader())
        uartPollPaused = false
        return true
    }

    /** Let the poller leave JNI before any UART stop. shutdownNow() here crashes DeviceAPI. */
    private fun stopPollingThread() {
        pollerActive = false
        uartPollPaused = true
        val t0 = SystemClock.elapsedRealtime()
        while (!pollerParked && SystemClock.elapsedRealtime() - t0 < 400L) {
            try {
                Thread.sleep(10L)
            } catch (_: InterruptedException) {
                break
            }
        }
        executorService?.shutdown()
        executorService = null
        pollerParked = true
    }

    private fun drainStaleBuffer() {
        var drained = 0
        while (drained < 64) {
            val tag = uhf().readTagFromBuffer() ?: break
            if (tag.first.isBlank()) break
            drained++
        }
    }

    private fun startPollingThread(inventory: Boolean, useTray: Boolean) {
        pollerActive = true
        pollerParked = false
        executorService = Executors.newSingleThreadExecutor()
        executorService?.execute {
            try {
                while (pollerActive && isScanning) {
                    try {
                        if (uartPollPaused) {
                            pollerParked = true
                            Thread.sleep(15)
                            continue
                        }
                        pollerParked = false
                        if (useTray) {
                            var tagInfo = trayManager.readTagFromBuffer()
                            if (tagInfo == null) {
                                Thread.sleep(1)
                                continue
                            }
                            do {
                                val epc = tagInfo?.epc ?: tagInfo?.getEPC()
                                if (!epc.isNullOrBlank()) {
                                    val cleanEpc = normalizeScanKey(epc)
                                    val rssi = tagInfo?.rssi ?: ""
                                    handleTagRead(cleanEpc, rssi, inventory)
                                }
                                tagInfo = trayManager.readTagFromBuffer()
                            } while (tagInfo != null && pollerActive && isScanning)
                        } else {
                            var pair = uhf().readTagFromBuffer()
                            if (pair == null) {
                                if (!inventory) tickSearchLedBlink()
                                Thread.sleep(1)
                                continue
                            }
                            do {
                                val cleanEpc = normalizeScanKey(pair!!.first)
                                if (cleanEpc.isNotEmpty()) {
                                    handleTagRead(cleanEpc, pair.second, inventory)
                                }
                                pair = uhf().readTagFromBuffer()
                            } while (pair != null && pollerActive && isScanning)
                            if (!inventory) tickSearchLedBlink()
                        }
                    } catch (_: InterruptedException) {
                        break
                    } catch (e: Throwable) {
                        e.printStackTrace()
                        try {
                            Thread.sleep(5)
                        } catch (_: Exception) {
                        }
                    }
                }
            } finally {
                pollerParked = true
            }
        }
    }

    private fun handleTagRead(cleanEpc: String, rssi: String, inventory: Boolean) {
        // Sparkle SearchViewModel: RSSI proximity tones. LED blink is inventory-mode
        // (uhf-uart-demo Tag LED Inventory), not stopInventory + Reserved-bank read.
        val searchHit = !inventory && matchesSearchTag(cleanEpc)
        val rssiTrim = rssi.trim()
        val rssiOut = if (searchHit && (rssiTrim.isEmpty() || rssiTrim == "0")) "-60" else rssi
        if (searchHit) {
            lastSearchHitAt = SystemClock.elapsedRealtime()
            playRssiSearchSound(rssiOut)
            noteFoundSearchLed(cleanEpc)
        }

        val emitEpc = if (searchHit) (resolveSearchEpc(cleanEpc) ?: cleanEpc) else cleanEpc
        if (!shouldEmitTagToFlutter(emitEpc, rssiOut)) {
            return
        }
        queueTagEvent(emitEpc, rssiOut, flushNow = searchHit)
    }

    /** Matches Flutter SearchScreen.convertRssiToProximity (abs RSSI → 0–100). */
    private fun rssiToProximityPercent(rssi: String): Int {
        val magnitude = try {
            kotlin.math.abs(rssi.trim().toFloat())
        } catch (_: Exception) {
            return 0
        }
        return (((80f - magnitude).coerceIn(0f, 40f)) * 100f / 40f).toInt().coerceIn(0, 100)
    }

    private fun shouldEmitTagToFlutter(cleanEpc: String, rssi: String = ""): Boolean {
        if (!trayModeEnabled && !r6ModeEnabled) {
                if (inventoryScanMode) {
                    if (matchEpcs.isNotEmpty() && !matchEpcs.contains(cleanEpc)) return false
                } else {
                    val hasSearch = synchronized(searchTagLock) { searchTags.isNotEmpty() }
                    when {
                        hasSearch -> if (!matchesSearchTag(cleanEpc)) return false
                        matchEpcs.isNotEmpty() -> if (!matchEpcs.contains(cleanEpc)) return false
                    }
                }
        }
        val now = System.currentTimeMillis()
        val isSearchTag = matchesSearchTag(cleanEpc)
        synchronized(recentEmitAt) {
            val last = recentEmitAt[cleanEpc] ?: 0L
            if (isSearchTag && rssi.isNotBlank()) {
                val prox = rssiToProximityPercent(rssi)
                val lastProx = recentEmitProx[cleanEpc]
                if (lastProx != null && prox != lastProx) {
                    recentEmitAt[cleanEpc] = now
                    recentEmitProx[cleanEpc] = prox
                    return true
                }
                if (now - last < searchEmitDedupMs) return false
                recentEmitAt[cleanEpc] = now
                recentEmitProx[cleanEpc] = prox
                return true
            }
            if (now - last < emitDedupMs) return false
            recentEmitAt[cleanEpc] = now
            if (recentEmitAt.size > 12000) {
                recentEmitAt.clear()
                recentEmitProx.clear()
            }
        }
        return true
    }

    private fun queueTagEvent(cleanEpc: String, rssi: String, flushNow: Boolean = false) {
        synchronized(pendingTagLock) {
            // Cap batch size so unmatched floods cannot blow the Flutter event binder.
            // Never drop a matched search tag — Pushpa HashMap never misses a hit.
            if (pendingTagEvents.size >= 300) {
                if (matchesSearchTag(cleanEpc)) {
                    pendingTagEvents.removeAt(0)
                } else {
                    return
                }
            }
            pendingTagEvents.add("$cleanEpc,$rssi")
            if (!tagFlushScheduled) {
                tagFlushScheduled = true
                val delay = if (flushNow) 0L else tagFlushDelayMs
                mainHandler.postDelayed({ flushQueuedTagEvents() }, delay)
            }
        }
    }

    private fun flushQueuedTagEvents() {
        val batch: List<String>
        synchronized(pendingTagLock) {
            tagFlushScheduled = false
            if (pendingTagEvents.isEmpty()) return
            batch = ArrayList(pendingTagEvents)
            pendingTagEvents.clear()
        }
        if (batch.size == 1) {
            eventSink?.success(batch[0])
        } else {
            eventSink?.success("BATCH:" + batch.joinToString("|"))
        }
    }

    private fun startInventoryLoopSound() {
        try {
            if (inventoryMediaPlayer == null) {
                val resId = activity.resources.getIdentifier("barcodebeep", "raw", activity.packageName)
                if (resId != 0) {
                    inventoryMediaPlayer = MediaPlayer.create(activity, resId)
                    inventoryMediaPlayer?.isLooping = true
                }
            }
            if (inventoryMediaPlayer?.isPlaying != true) {
                inventoryMediaPlayer?.start()
            }
        } catch (e: Throwable) {
            e.printStackTrace()
        }
    }

    private fun stopInventoryLoopSound() {
        try {
            inventoryMediaPlayer?.stop()
            inventoryMediaPlayer?.release()
            inventoryMediaPlayer = null
        } catch (_: Throwable) {
            inventoryMediaPlayer = null
        }
    }

    private fun ensureSoundPool() {
        if (soundPoolReady) return
        initSoundPool()
        soundPoolReady = true
    }

    private fun initSoundPool() {
        try {
            audioManager = activity.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            soundPool = SoundPool.Builder()
                .setMaxStreams(10)
                .setAudioAttributes(audioAttributes)
                .build()

            // Same mapping as Sparkle RFIDReaderManager.initSounds()
            soundMap[1] = loadSound("barcodebeep")
            soundMap[2] = loadSound("sixty")
            soundMap[3] = loadSound("seventy")
            soundMap[4] = loadSound("fourty")
            soundMap[5] = loadSound("found2")
        } catch (e: Throwable) {
            e.printStackTrace()
        }
    }

    private fun loadSound(name: String): Int {
        val resId = activity.resources.getIdentifier(name, "raw", activity.packageName)
        return if (resId != 0) {
            soundPool?.load(activity, resId, 1) ?: 0
        } else {
            0
        }
    }

    /** Sparkle RFIDReaderManager.playSound(id, loop). */
    private fun playSound(id: Int, loop: Int = 0) {
        try {
            ensureSoundPool()
            soundStreamIds.values.forEach { streamId -> soundPool?.stop(streamId) }
            soundStreamIds.clear()

            val maxVol = audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC)?.toFloat() ?: 1f
            val curVol = audioManager?.getStreamVolume(AudioManager.STREAM_MUSIC)?.toFloat() ?: 1f
            volumeRatio = if (maxVol > 0f) curVol / maxVol else 1f

            val soundId = soundMap[id] ?: return
            if (soundId == 0) return
            val streamId = soundPool?.play(
                soundId,
                volumeRatio,
                volumeRatio,
                1,
                loop,
                1f,
            ) ?: return
            soundStreamIds[id] = streamId
        } catch (e: Throwable) {
            e.printStackTrace()
        }
    }

    private fun stopSound(id: Int) {
        val streamId = soundStreamIds[id] ?: return
        soundPool?.stop(streamId)
        soundStreamIds.remove(id)
    }

    private fun stopAllSounds() {
        soundStreamIds.values.forEach { streamId -> soundPool?.stop(streamId) }
        soundStreamIds.clear()
    }

    /**
     * Sparkle SearchViewModel RSSI → sound id buckets:
     * abs(rssi) <50 → fourty(4), <60 → sixty(2), <70 → found2(5), else barcodebeep(1).
     * Keep the close tone while the gun stays on the tag; only move to a farther
     * tone after weaker RSSI lasts past [holdCloseSearchMs] (or a closer tone).
     */
    private fun playRssiSearchSound(rssi: String) {
        val rssiAbs = try {
            kotlin.math.abs(rssi.trim().toDouble())
        } catch (_: Exception) {
            0.0
        }
        var id = when {
            rssiAbs > 0 && rssiAbs < 50 -> 4
            rssiAbs > 50 && rssiAbs < 60 -> 2
            rssiAbs > 60 && rssiAbs < 70 -> 5
            rssiAbs > 70 -> 1
            else -> -1
        }
        if (id == -1) return
        val now = System.currentTimeMillis()
        val closer = lastSearchSoundId <= 0 || searchSoundRank(id) < searchSoundRank(lastSearchSoundId)
        if (searchSoundRank(id) <= 1) {
            lastCloseSearchSoundAt = now
        }
        if (!closer && now - lastCloseSearchSoundAt < holdCloseSearchMs && lastSearchSoundId > 0) {
            id = lastSearchSoundId
        }
        if (id == lastSearchSoundId) {
            if (now - lastSearchSoundPlayAt < searchSoundMinIntervalMs) return
        } else if (now - lastSearchSoundPlayAt < searchSoundSwitchMinMs) {
            return
        }
        lastSearchSoundPlayAt = now
        if (lastSearchSoundId > 0 && lastSearchSoundId != id) {
            stopSound(lastSearchSoundId)
        }
        lastSearchSoundId = id
        playSearchTone(id)
    }

    /**
     * Search RSSI beep without [playSound]'s stop-all. Restarting every tag read
     * after LED blink mode made the tone choppy.
     */
    private fun playSearchTone(id: Int) {
        try {
            ensureSoundPool()
            val soundId = soundMap[id] ?: return
            if (soundId == 0) return
            soundStreamIds[id]?.let { prev ->
                soundPool?.stop(prev)
                soundStreamIds.remove(id)
            }
            val maxVol = audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC)?.toFloat() ?: 1f
            val curVol = audioManager?.getStreamVolume(AudioManager.STREAM_MUSIC)?.toFloat() ?: 1f
            volumeRatio = if (maxVol > 0f) curVol / maxVol else 1f
            val streamId = soundPool?.play(
                soundId,
                volumeRatio,
                volumeRatio,
                1,
                0,
                1f,
            ) ?: return
            soundStreamIds[id] = streamId
        } catch (e: Throwable) {
            e.printStackTrace()
        }
    }

    /** 0 = closest (fourty), 3 = farthest (barcodebeep). */
    private fun searchSoundRank(id: Int): Int = when (id) {
        4 -> 0
        2 -> 1
        5 -> 2
        1 -> 3
        else -> 4
    }

    companion object {
        private const val TAG = "HardwareController"
        private const val SEARCH_LED_WAIT = 0
        private const val SEARCH_LED_BLINK = 1
        private const val SEARCH_LED_DISCOVER = 2
        private const val SEARCH_LED_MAX = 8
        /** Wait after the last newly-found tag so a pile of 3 is applied together. */
        private const val SEARCH_LED_GATHER_MS = 280L
        private const val SEARCH_LED_GATHER_MAX_MS = 800L
        /** EPC window so normal tags keep scanning. */
        private const val SEARCH_LED_SCAN_MS = 550L
        /** Keep LabelStock LEDs on, then return to EPC for other tags. */
        private const val SEARCH_LED_BLINK_MS = 1400L
        private const val SEARCH_LED_HIT_TIMEOUT_MS = 700L
        private const val SEARCH_RADIO_EPC = 0
        private const val SEARCH_RADIO_FILTER = 1
        private const val SEARCH_RADIO_ALL = 2
    }
}
