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
import java.util.concurrent.TimeUnit

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

    @Volatile private var isScanning = false
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
    /** Loudest search tone reached. Weaker reads must not silence it. */
    private var bestSearchSoundId = -1
    /** Search tone only. Inventory start must not be tied to this. */
    @Volatile private var searchSoundEnabled = false
    /** Bumped on Stop so a tone that starts late is silenced, not left looping. */
    @Volatile private var searchToneGeneration = 0
    private val soundLock = Any()
    /** Allow a closer bucket to switch without waiting a full beep. */
    private val searchSoundSwitchMinMs = 45L
    /** Ignore brief weaker RSSI so close tone does not flip to far. */
    private var lastCloseSearchSoundAt = 0L

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
    /** filter = one searched chip; list = only the open list; all = every LED; epc = no LED. */
    @Volatile private var searchRadioMode = SEARCH_RADIO_EPC
    /** List search lights every list chip the gun reads. One-tag search stays on that chip. */
    @Volatile private var searchLedMulti = false
    /**
     * LED Tag solid was applied by LedTagSolid (rfid_flutter_plugin) before start.
     * Do not setEPCMode or blink-revert — that turns the solid light off.
     */
    @Volatile private var holdLedSolid = false
    /** Continuous inventory holds a tag LED solid. Pulse stop/start so it blinks. */
    @Volatile private var tagLedBlinkOn = false
    @Volatile private var ledLightOn = true
    @Volatile private var ledPhaseUntil = 0L
    /** One UART queue — start/stop/LED must not overlap (that fails startInventory). */
    private val uartExecutor = Executors.newSingleThreadExecutor()
    @Volatile private var uartPollPaused = false
    @Volatile private var pollerActive = false
    @Volatile private var pollerParked = true
    @Volatile private var pollerThread: Thread? = null
    @Volatile private var pollerBeatAt = 0L
    private var matchEpcs = HashSet<String>()
    @Volatile private var inventoryScanMode = false
    @Volatile private var scanningPermitted = false
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
    private var scanArmedAt = 0L
    private var firstTagLogged = false
    private var droppedTagEvents = 0

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
        tagLedBlinkOn = false
        ledLightOn = true
        ledPhaseUntil = 0L
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
    @Volatile private var activeInventorySession = false
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
        uartExecutor.execute {
            try {
                ensureBarcodeManager()
                barcodeManager.startScan()
            } catch (_: Throwable) {
            }
        }
    }

    override fun release() {
        isScanning = false
        scanningPermitted = false
        pollerActive = false
        try {
            // Same UART thread as start/stop. free() only if this process
            // still owns the module, so the next launch can open the port.
            // Cap the wait so destroy cannot sit on the UI thread.
            val closing = uartExecutor.submit {
                try {
                    stopRfidInventory()
                } catch (_: Throwable) {
                }
                try {
                    uhfFacade?.closeQuietly()
                } catch (_: Throwable) {
                }
            }
            try {
                closing.get(1500L, TimeUnit.MILLISECONDS)
            } catch (_: Throwable) {
            }
        } catch (_: Throwable) {
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
        // Do not construct the BLE reader or barcode engine here. The first
        // method call is isSupported/initReader on the UI thread, and loading
        // DeviceAPI there shows "isn't responding" on every launch.
        when (call.method) {
            "initReader" -> {
                uartExecutor.execute {
                    val ok = try {
                        if (trayModeEnabled || r6ModeEnabled) {
                            ensureTrayManager()
                            trayManager.isConnected || trayManager.init()
                        } else {
                            uhf().initHardware()
                        }
                    } catch (e: Throwable) {
                        Log.e(TAG, "initReader bg failed", e)
                        false
                    }
                    mainHandler.post { result.success(ok) }
                }
            }
            "prepareForScan" -> {
                scanningPermitted = true
                result.success(true)
            }
            "haltScan" -> {
                haltScan()
                // Same queue as start/stop. A main-thread clear used to land
                // while start was opening the reader and then drop every tag.
                uartExecutor.execute {
                    scanningPermitted = false
                    mainHandler.post { result.success(true) }
                }
            }
            "startScanning" -> {
                val power = call.argument<Int>("power") ?: 5
                val inventory = call.argument<Boolean>("inventory") ?: inventoryScanMode
                val playStartSound = call.argument<Boolean>("playStartSound") ?: true
                lastScanPower = power
                if (!inventory) {
                    val ledMode = call.argument<String>("ledMode")?.trim()?.lowercase()
                    searchLedMulti = ledMode == "list"
                    searchRadioMode = when (ledMode) {
                        "filter", "list" -> SEARCH_RADIO_FILTER
                        "all" -> SEARCH_RADIO_ALL
                        else -> SEARCH_RADIO_EPC
                    }
                    holdLedSolid = call.argument<Boolean>("holdLedSolid") == true
                } else {
                    holdLedSolid = false
                    searchLedMulti = false
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
                tagSetExecutor.execute {
                    matchEpcs.clear()
                    synchronized(searchTagLock) {
                        searchTags.clear()
                        searchLedEpcs.clear()
                    }
                    resetSearchLedFoundState()
                    for (tag in tags) addSearchKey(tag)
                    mainHandler.post { result.success(true) }
                }
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
                tagSetExecutor.execute {
                    for (tag in tags) addSearchKey(tag)
                    mainHandler.post { result.success(true) }
                }
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
            "primeSearchSound" -> {
                val id = call.argument<Int>("id") ?: -1
                if (id > 0) {
                    ensureSoundPool()
                    val now = System.currentTimeMillis()
                    lastSearchSoundId = id
                    lastSearchSoundPlayAt = now
                    if (searchSoundRank(id) <= 1) {
                        lastCloseSearchSoundAt = now
                    }
                    playSearchTone(id)
                }
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
                searchSoundEnabled = false
                val id = call.argument<Int>("id")
                if (id != null) {
                    stopSound(id, force = true)
                } else {
                    stopAllSounds(force = true)
                }
                lastSearchSoundId = -1
                bestSearchSoundId = -1
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
                // An open search keeps its tone until the user stops scanning.
                if (!searchSessionActive()) {
                    stopAllSounds()
                    lastSearchSoundId = -1
                    bestSearchSoundId = -1
                }
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
                            ensureTrayManager()
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
                uartExecutor.execute {
                    val list = try {
                        listSystemConnectedBluetoothDevices()
                    } catch (e: Throwable) {
                        Log.e(TAG, "listSystemConnectedBluetoothDevices", e)
                        emptyList()
                    }
                    mainHandler.post { result.success(list) }
                }
            }
            "getTrayStatus" -> result.success(trayStatusMap())
            "getR6Status" -> result.success(r6StatusMap())
            "openBarcode" -> {
                uartExecutor.execute {
                    val ok = try {
                        ensureBarcodeManager()
                        barcodeManager.openIfNeeded()
                    } catch (_: Throwable) {
                        false
                    }
                    mainHandler.post { result.success(ok) }
                }
            }
            "startBarcodeScan" -> {
                uartExecutor.execute {
                    val ok = try {
                        ensureBarcodeManager()
                        barcodeManager.startScan()
                    } catch (_: Throwable) {
                        false
                    }
                    mainHandler.post { result.success(ok) }
                }
            }
            "stopBarcodeScan" -> {
                uartExecutor.execute {
                    try {
                        if (::barcodeManager.isInitialized) barcodeManager.stopScan()
                    } catch (_: Throwable) {
                    }
                    mainHandler.post { result.success(true) }
                }
            }
            "closeBarcode" -> {
                uartExecutor.execute {
                    try {
                        if (::barcodeManager.isInitialized) barcodeManager.close()
                    } catch (_: Throwable) {
                    }
                    mainHandler.post { result.success(true) }
                }
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

    private fun ensureBarcodeManager() {
        if (::barcodeManager.isInitialized) return
        barcodeManager = BarcodeManager(activity)
        barcodeManager.setOnScanned { data ->
            activity.runOnUiThread {
                eventSink?.success("BARCODE:$data")
            }
        }
    }

    private fun ensureTrayManager() {
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
                ensureTrayManager()
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
        val ready = ::trayManager.isInitialized
        map["enabled"] = r6ModeEnabled
        map["connected"] = r6ModeEnabled && ready &&
            (trayManager.isReallyConnected() || trayManager.isConnected)
        map["address"] = r6DeviceAddress
        map["connecting"] = r6ModeEnabled && ready &&
            (trayManager.isConnecting || bleConnectQueued)
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
        holdLedSolid = false
        inventoryScanMode = false
        inventoryScopeEpcs.clear()
        sessionUniqueEpcs.clear()
        searchSoundEnabled = false
        stopAllSounds(force = true)
        lastSearchSoundId = -1
        bestSearchSoundId = -1
        stopInventoryLoopSound()
    }

    /**
     * Scan Display UART start, same sequence as main: open, set power, start once.
     * Does not clear Search LED filters and does not power the module off.
     */
    private fun startPlainUartInventory(power: Int): Boolean {
        inventoryScanMode = true
        scanningPermitted = true
        uhf().initHardware()
        uhf().prepareInventory(power)
        drainStaleBuffer()
        clearSearchLedTagCallback()
        startInventoryLoopSound()
        var started = uhf().startInventory()
        if (!started) {
            try {
                uhf().stopInventory()
            } catch (_: Throwable) {
            }
            try {
                Thread.sleep(100L)
            } catch (_: InterruptedException) {
            }
            uhf().prepareInventory(power)
            drainStaleBuffer()
            started = uhf().startInventory()
            Log.i(TAG, "startInventory retry => $started")
        }
        if (!started && uhf().reopenStalePort()) {
            uhf().prepareInventory(power)
            drainStaleBuffer()
            started = uhf().startInventory()
            Log.i(TAG, "startInventory after reopen => $started")
        }
        if (started) {
            inventoryScanMode = true
            scanningPermitted = true
            isScanning = true
            scanArmedAt = SystemClock.elapsedRealtime()
            firstTagLogged = false
            droppedTagEvents = 0
            Log.i(TAG, "RFID reader-started inventory=true")
            startPollingThread(inventory = true, useTray = false)
        } else {
            isScanning = false
            stopInventoryLoopSound()
        }
        return started
    }

    private fun startRfidInventory(power: Int, inventory: Boolean, playStartSound: Boolean = true): Boolean {
        scanningPermitted = true
        lastScanPower = power
        if (isScanning) {
            // Leftover LED/inventory session would keep an old EPC filter and
            // miss the new Global Search item. Restart Search at the requested power.
            // stopRfidInventory clears holdLedSolid; this start already asked to keep it.
            val keepSolid = holdLedSolid
            if (trayModeEnabled || r6ModeEnabled) {
                if (trayManager.isReallyConnected() && pollerHealthy()) {
                    return true
                }
                Log.w(TAG, "Stale BLE isScanning — restart inventory")
                isScanning = false
                stopPollingThread()
            } else if (!inventory) {
                stopRfidInventory(restoreEpc = !keepSolid)
                holdLedSolid = keepSolid
                scanningPermitted = true
            } else if (
                uhf().modulePowered() && uhf().isInventorying() && pollerHealthy()
            ) {
                return true
            } else {
                Log.w(TAG, "Stale UART inventory — restart")
                stopRfidInventory()
                scanningPermitted = true
            }
        }
        searchSoundEnabled = false
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
            if (inventory) {
                return startPlainUartInventory(power)
            }
            if (!uhf().initHardware() && !uhf().recoverHardware()) {
                Log.e(TAG, "startRfidInventory: initHardware failed")
                stopInventoryLoopSound()
                return false
            }
            applySearchLedBlinkModeIfNeeded(false)
            clearSearchLedTagCallback()
            // Stop leftover inventory so LED Tag mode + filter apply cleanly.
            try {
                uhf().stopInventory()
            } catch (_: Throwable) {
            }
            try {
                Thread.sleep(15L)
            } catch (_: InterruptedException) {
            }
            prepareSearchRadio(power)
            // Accept callback tags immediately. LED chips often arrive on
            // setInventoryCallback before the poller thread is up.
            isScanning = true
            searchSoundEnabled = true
            armSearchRangeWatch()
            attachSearchLedTagCallback()
            if (playStartSound) playSound(1, 0)
            // A leftover "already start" flag is not a live read. Wait until
            // it clears, then open a real inventory. Do not power the module off.
            if (uhf().isInventorying()) {
                try {
                    uhf().stopInventory()
                } catch (_: Throwable) {
                }
                val waitFrom = SystemClock.elapsedRealtime()
                while (uhf().isInventorying() && SystemClock.elapsedRealtime() - waitFrom < 300L) {
                    try {
                        Thread.sleep(20L)
                    } catch (_: InterruptedException) {
                        break
                    }
                }
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
                    attachInventoryTagCallback()
                } else {
                    prepareSearchRadio(power)
                    attachSearchLedTagCallback()
                }
                started = uhf().startInventory()
                Log.i(TAG, "startInventory attempt=2 => $started")
            }
            if (!started) {
                try {
                    uhf().stopInventory()
                } catch (_: Throwable) {
                }
                try {
                    Thread.sleep(250L)
                } catch (_: InterruptedException) {
                }
                if (inventory) {
                    uhf().prepareScan(power)
                    attachInventoryTagCallback()
                } else {
                    prepareSearchRadio(power)
                    attachSearchLedTagCallback()
                }
                started = uhf().startInventory()
                Log.i(TAG, "startInventory attempt=3 => $started")
            }
            if (!started) {
                Log.w(TAG, "startInventory failed — recoverHardware")
                if (uhf().recoverHardware()) {
                    if (inventory) {
                        uhf().prepareScan(power)
                        attachInventoryTagCallback()
                    } else {
                        prepareSearchRadio(power)
                        attachSearchLedTagCallback()
                    }
                    started = uhf().startInventory()
                    Log.i(TAG, "startInventory attempt=4 recover => $started")
                }
            }
            if (!started && uhf().reopenStalePort()) {
                if (inventory) {
                    uhf().prepareScan(power)
                    attachInventoryTagCallback()
                } else {
                    prepareSearchRadio(power)
                    attachSearchLedTagCallback()
                }
                started = uhf().startInventory()
                Log.i(TAG, "startInventory attempt=5 reopen => $started")
            }
            if (started) {
                // A stop that landed while init was running must not swallow tags.
                scanningPermitted = true
                isScanning = true
                scanArmedAt = SystemClock.elapsedRealtime()
                firstTagLogged = false
                droppedTagEvents = 0
                Log.i(TAG, "RFID reader-started inventory=$inventory")
                startPollingThread(inventory, useTray = false)
            } else {
                isScanning = false
                searchSoundEnabled = false
                clearSearchLedTagCallback()
                stopInventoryLoopSound()
            }
            started
        } catch (e: Throwable) {
            e.printStackTrace()
            isScanning = false
            searchSoundEnabled = false
            stopInventoryLoopSound()
            false
        }
    }

    private fun startR6InventoryGuarded(power: Int, inventory: Boolean, playStartSound: Boolean = true): Boolean {
        scanningPermitted = true
        if (isScanning) {
            if (trayManager.isReallyConnected() && pollerHealthy()) {
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
        if (holdLedSolid) {
            // Plugin set MODE_LED_TAG solid. Re-apply blink times on the same mode.
            uhf().applyLedTagSolidMode()
            tagLedBlinkOn = true
            ledLightOn = true
            ledPhaseUntil = 0L
            Log.i(TAG, "Search LED blink on plugin filter mode=$searchRadioMode")
            searchLedAppliedKey = ""
            searchLedPhase = SEARCH_LED_BLINK
            searchLedPhaseUntil = 0L
            foundLedGatherUntil = 0L
            foundLedGatherDeadline = 0L
            return
        }
        // A list must not use an empty LED filter — that lights every tag in
        // range, including ones that are not on the list. Read in EPC first so
        // the scan and beep start immediately, then blink only chips that were
        // actually read. Filtering the whole catalog up front locked the gun
        // onto a few chips, startInventory returned "already start", and the
        // session died: no scan, no sound, no LED.
        if (searchLedMulti) {
            uhf().prepareScan(power)
            tagLedBlinkOn = false
            ledLightOn = true
            ledPhaseUntil = 0L
            searchLedAppliedKey = ""
            searchLedPhase = SEARCH_LED_DISCOVER
            searchLedPhaseUntil = 0L
            foundLedGatherUntil = 0L
            foundLedGatherDeadline = 0L
            Log.i(TAG, "List search EPC discover — LED only after a list hit")
            return
        }
        if (searchRadioMode == SEARCH_RADIO_ALL) {
            val ok = uhf().applyLedBlinkInventoryNoFilter()
            Log.i(TAG, "Tag LED Inventory unfiltered (LED+normal) multi=$searchLedMulti => $ok")
            if (!ok) {
                uhf().prepareScan(power)
            }
            tagLedBlinkOn = ok
            ledLightOn = true
            ledPhaseUntil = 0L
            searchLedAppliedKey = ""
            searchLedPhase = if (ok) SEARCH_LED_DISCOVER else SEARCH_LED_WAIT
            searchLedPhaseUntil = 0L
            foundLedGatherUntil = 0L
            foundLedGatherDeadline = 0L
            return
        }
        // Known 24/32 chip: light it now. Waiting for a live read adds the delay.
        if (searchRadioMode == SEARCH_RADIO_FILTER) {
            val chips = catalogChipEpcs()
            if (chips.isNotEmpty() && uhf().applyLedTagBlinkMode(chips)) {
                tagLedBlinkOn = true
                ledLightOn = true
                ledPhaseUntil = 0L
                Log.i(TAG, "Search LED blink immediate epcs=${chips.size}")
                searchLedAppliedKey = searchLedKey(chips)
                searchLedPhase = SEARCH_LED_BLINK
                searchLedPhaseUntil = 0L
                foundLedGatherUntil = 0L
                foundLedGatherDeadline = 0L
                lastSearchHitAt = 0L
                return
            }
        }
        // Item code (SP24) is not a chip EPC. Read once, then lock that live EPC.
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

    /**
     * Chip id for the LED filter. A shared 24-hex header used to merge three
     * different 128-bit tags into one select, so the list showed 3 scans and
     * only one LED.
     */
    private fun ledEpcOf(cleanEpc: String): String? {
        if (resolveSearchEpc(cleanEpc) == null) return null
        if (cleanEpc.length >= 32) {
            val p32 = cleanEpc.substring(0, 32)
            if (isChipEpcHex(p32)) return p32
        }
        if (isChipEpcHex(cleanEpc)) return cleanEpc
        if (cleanEpc.length >= 24) {
            val p24 = cleanEpc.substring(0, 24)
            if (isChipEpcHex(p24)) return p24
        }
        if (isLedFilterHex(cleanEpc) && cleanEpc.length <= 32) return cleanEpc
        val resolved = resolveSearchEpc(cleanEpc) ?: return null
        if (resolved.length >= 32 && isChipEpcHex(resolved.substring(0, 32))) {
            return resolved.substring(0, 32)
        }
        if (isChipEpcHex(resolved)) return resolved
        if (resolved.length >= 24 && isChipEpcHex(resolved.substring(0, 24))) {
            return resolved.substring(0, 24)
        }
        return if (isLedFilterHex(resolved) && resolved.length <= 32) resolved else null
    }

    /**
     * One chip per tag. Drop a 24-hex key that is only the head of a 32-hex
     * key already in the set, so the reader select stays on the full EPC.
     */
    private fun distinctLedChips(raw: Collection<String>): List<String> {
        val chips = LinkedHashSet<String>()
        for (rawEpc in raw) {
            val epc = rawEpc.trim().uppercase()
            when {
                epc.length >= 32 && isChipEpcHex(epc.substring(0, 32)) ->
                    chips.add(epc.substring(0, 32))
                isChipEpcHex(epc) -> chips.add(epc)
                isLedFilterHex(epc) && epc.length <= 32 -> chips.add(epc)
            }
        }
        return chips.sorted()
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
            while (foundLedEpcs.size > SEARCH_LED_REMEMBER) {
                val oldest = foundLedEpcs.keys.first()
                foundLedEpcs.remove(oldest)
            }
            if (isNew) {
                if (searchLedMulti) {
                    // Do not lock 1–2 tags. Every new list chip restarts the wait
                    // so the 3rd tag is in the same solid filter.
                    foundLedGatherUntil = now + 800L
                } else {
                    foundLedGatherUntil = now
                    if (foundLedGatherDeadline == 0L) foundLedGatherDeadline = now
                }
            }
        }
    }

    private fun tickSearchLedBlink() {
        // Plugin LED is already set. Do not clear it here.
        if (holdLedSolid) return
        // One searched tag stays on that chip. A list keeps adding every match.
        if (!searchLedMulti &&
            searchRadioMode == SEARCH_RADIO_FILTER &&
            searchLedPhase == SEARCH_LED_BLINK &&
            searchLedAppliedKey.isNotEmpty()
        ) {
            return
        }
        // Only the open list. Unfiltered LED mode lights tags that are not on it.
        if (searchRadioMode != SEARCH_RADIO_FILTER) return
        if (searchLedApplyBusy || uartPollPaused) return
        if (!isScanning || activeInventorySession || trayModeEnabled || r6ModeEnabled) return
        val now = SystemClock.elapsedRealtime()
        val found = synchronized(foundLedLock) {
            foundLedEpcs.keys.filter { it !in searchEpcOnly }
        }
        if (found.isEmpty()) return
        if (searchLedMulti) {
            // Leave this scan in EPC. Locking the LED select stops the reader
            // and later tags never update their percent. Do not stop it here.
            return
        }
        if (searchLedKey(found) == searchLedAppliedKey) return
        val wantLock = if (foundLedGatherUntil <= 0L) {
            true
        } else {
            now >= foundLedGatherUntil ||
                (foundLedGatherDeadline > 0L && now >= foundLedGatherDeadline)
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
                Thread.sleep(15L)
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
    /** Inventory tags also arrive on setInventoryCallback — do not treat as Search. */
    private fun attachInventoryTagCallback() {
        try {
            uhf().setInventoryCallback { epc, rssi ->
                if (!scanningPermitted) return@setInventoryCallback
                val cleanEpc = normalizeScanKey(epc)
                if (cleanEpc.isEmpty()) return@setInventoryCallback
                handleTagRead(cleanEpc, rssi, inventory = true)
            }
            searchLedCallbackAttached = true
        } catch (e: Throwable) {
            searchLedCallbackAttached = false
            Log.w(TAG, "Inventory tag callback failed: ${e.message}")
        }
    }

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
            if (searchLedMulti) drainSearchBufferIntoFound()
            val target = if (searchLedMulti) {
                val live = currentListLedEpcs()
                if (live.isNotEmpty()) live else epcs
            } else {
                epcs
            }
            if (searchLedPhase == SEARCH_LED_BLINK && searchLedKey(target) == searchLedAppliedKey) return
            val filtered = uhf().applyLedTagBlinkMode(target)
            Log.i(TAG, "Search LED solid filter epcs=${target.size} => $filtered")
            attachSearchLedTagCallback()
            resumeSearchInventoryRunning()
            if (filtered && isScanning) {
                uhf().reassertLedSolidIfCleared()
                // Solid stays on. The stop/start pulse was turning the 3rd tag off.
                tagLedBlinkOn = false
                ledLightOn = true
                ledPhaseUntil = 0L
                searchLedAppliedKey = searchLedKey(target)
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
            Thread.sleep(20L)
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

    private fun currentListLedEpcs(): List<String> {
        val raw = synchronized(foundLedLock) {
            foundLedEpcs.keys.filter { it !in searchEpcOnly }
        }
        return distinctLedChips(raw)
    }

    /** True when every live chip is already in the filter that is blinking. */
    private fun ledFilterCovers(live: Collection<String>): Boolean {
        if (searchLedAppliedKey.isEmpty()) return false
        val have = searchLedAppliedKey.split(',').toSet()
        return live.all { it in have }
    }

    /**
     * Apply every scanned list chip together, same order every time.
     * A rotating or one-tag filter is what made the count jump between 0, 1, and 2.
     * Chips already blinking stay in the set so a later read cannot drop them.
     */
    private fun lightEveryScannedListTag() {
        val merged = LinkedHashSet<String>()
        if (searchLedAppliedKey.isNotEmpty()) {
            merged.addAll(searchLedAppliedKey.split(',').filter { it.isNotEmpty() })
        }
        merged.addAll(currentListLedEpcs())
        val all = distinctLedChips(merged)
        if (all.isEmpty()) return
        val count = minOf(all.size, SEARCH_LED_MAX)
        val stable = ArrayList(all.take(count))
        if (searchLedKey(stable) == searchLedAppliedKey) return
        val ok = try {
            uhf().applyLedTagBlinkMode(stable)
        } catch (_: Throwable) {
            false
        }
        if (!ok) {
            Log.w(TAG, "List LED filter failed n=${stable.size}")
            return
        }
        searchLedAppliedKey = searchLedKey(stable)
        Log.i(TAG, "List LED blink n=${stable.size}")
    }

    /**
     * MODE_LED_TAG stays lit for the whole inventory, which looks solid.
     * Stop the field briefly so the tag goes dark, then start again.
     * Returns true while the light should stay off.
     */
    /** Read tags already in the UART buffer before the solid filter is applied. */
    private fun drainSearchBufferIntoFound() {
        var n = 0
        while (n < 64) {
            val tag = try {
                uhf().readTagFromBuffer()
            } catch (_: Throwable) {
                null
            } ?: break
            val epc = normalizeScanKey(tag.first)
            if (epc.isNotEmpty()) handleTagRead(epc, tag.second, inventory = false)
            n++
        }
    }

    private fun tickLedBlinkDark(): Boolean {
        // List LEDs stay solid for every matched tag. Stopping inventory to
        // blink was leaving the last tag dark.
        if (searchLedMulti || !tagLedBlinkOn || activeInventorySession || !isScanning) return false
        if (trayModeEnabled || r6ModeEnabled) return false
        if (uartPollPaused || searchLedApplyBusy) return false
        val now = SystemClock.elapsedRealtime()
        if (!ledLightOn) {
            if (now < ledPhaseUntil) return true
            if (searchLedMulti) {
                val all = currentListLedEpcs()
                // Keep chips already in the filter. Replacing with only the
                // tags read so far drops the rest and they stay dark.
                if (all.isNotEmpty() && !ledFilterCovers(all)) {
                    lightEveryScannedListTag()
                }
            }
            // startInventory clears MODE_LED_TAG. The first flash works because
            // the handoff just set blink times. Every later flash must set them
            // again while the field is off, or the light stops after one blink.
            // Do not setFilter here — doing that on every flash freezes it solid.
            uhf().applyLedTagSolidMode()
            var started = uhf().startInventory()
            if (!started) {
                try {
                    uhf().stopInventory()
                } catch (_: Throwable) {
                }
                uhf().applyLedTagSolidMode()
                started = uhf().startInventory()
            }
            if (!started) {
                ledPhaseUntil = now + 40L
                return true
            }
            ledLightOn = true
            ledPhaseUntil = now + LED_BLINK_ON_MS
            return false
        }
        if (ledPhaseUntil == 0L) {
            ledPhaseUntil = now + LED_BLINK_ON_MS
            return false
        }
        if (now < ledPhaseUntil) return false
        try {
            uhf().stopInventory()
        } catch (_: Throwable) {
        }
        ledLightOn = false
        ledPhaseUntil = now + LED_BLINK_OFF_MS
        return true
    }

    private fun searchLedFailBackoff() {
        foundLedGatherUntil = SystemClock.elapsedRealtime() + 250L
        foundLedGatherDeadline = foundLedGatherUntil
    }

    private fun stopUartInventoryNow(useBle: Boolean, restoreEpc: Boolean = true) {
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
        if (!useBle && restoreEpc) {
            try {
                uhfFacade?.restoreEpcInventoryMode()
            } catch (_: Throwable) {
            }
        }
    }

    private fun stopRfidInventory(restoreEpc: Boolean = true): Boolean {
        if (scanArmedAt != 0L) {
            val ran = SystemClock.elapsedRealtime() - scanArmedAt
            Log.i(TAG, "RFID stop +${ran}ms unique=${sessionUniqueEpcs.size} dropped=$droppedTagEvents")
            scanArmedAt = 0L
        }
        isScanning = false
        searchSoundEnabled = false
        inventoryScanMode = false
        inventoryScopeEpcs.clear()
        sessionUniqueEpcs.clear()
        resetSearchLedFoundState()
        stopAllSounds(force = true)
        lastSearchSoundId = -1
        bestSearchSoundId = -1
        lastCloseSearchSoundAt = 0L
        stopInventoryLoopSound()
        holdLedSolid = false
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
        stopUartInventoryNow(useBleReader(), restoreEpc)
        uartPollPaused = false
        return true
    }

    /** Let the poller leave JNI before any UART stop. shutdownNow() here crashes DeviceAPI. */
    private fun stopPollingThread() {
        pollerActive = false
        pollerBeatAt = 0L
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

    private fun pollerHealthy(): Boolean {
        val thread = pollerThread
        return pollerActive && thread != null && thread.isAlive
    }

    private fun startPollingThread(inventory: Boolean, useTray: Boolean) {
        pollerActive = true
        pollerParked = false
        pollerBeatAt = 0L
        executorService = Executors.newSingleThreadExecutor()
        executorService?.execute {
            pollerThread = Thread.currentThread()
            try {
                while (pollerActive && isScanning) {
                    pollerBeatAt = SystemClock.elapsedRealtime()
                    try {
                        if (uartPollPaused) {
                            pollerParked = true
                            Thread.sleep(15)
                            continue
                        }
                        pollerParked = false
                        if (!inventory && !useTray && tickLedBlinkDark()) {
                            Thread.sleep(5)
                            continue
                        }
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
                            } while (
                                pair != null && pollerActive && isScanning &&
                                    !(tagLedBlinkOn && ledPhaseUntil > 0L &&
                                        SystemClock.elapsedRealtime() >= ledPhaseUntil)
                            )
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
                if (pollerThread === Thread.currentThread()) pollerThread = null
            }
        }
    }

    private fun handleTagRead(cleanEpc: String, rssi: String, inventory: Boolean) {
        // Sparkle SearchViewModel: RSSI proximity tones. LED blink is inventory-mode
        // (uhf-uart-demo Tag LED Inventory), not stopInventory + Reserved-bank read.
        val searchHit = !inventory && matchesSearchTag(cleanEpc)
        val rssiTrim = rssi.trim()
        val rssiMissing = rssiTrim.isEmpty() || rssiTrim == "0" || rssiTrim == "0.0"
        val rssiOut = rssi
        if (searchHit && isScanning && scanningPermitted) {
            lastSearchHitAt = SystemClock.elapsedRealtime()
            if (!rssiMissing) playRssiSearchSound(rssiOut)
            noteFoundSearchLed(cleanEpc)
        }

        val emitEpc = if (searchHit) (resolveSearchEpc(cleanEpc) ?: cleanEpc) else cleanEpc
        if (!shouldEmitTagToFlutter(emitEpc, rssiOut)) {
            return
        }
        val firstInventory = inventory && sessionUniqueEpcs.add(cleanEpc)
        if (!firstTagLogged) {
            firstTagLogged = true
            val waited = if (scanArmedAt == 0L) -1L else SystemClock.elapsedRealtime() - scanArmedAt
            Log.i(TAG, "RFID first-tag +${waited}ms unique=${sessionUniqueEpcs.size}")
        }
        queueTagEvent(emitEpc, rssiOut, flushNow = searchHit || firstInventory)
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
                // Ignore 1-point RSSI noise. A real step, or a heartbeat, still updates.
                if (lastProx != null &&
                    kotlin.math.abs(prox - lastProx) < 8 &&
                    now - last < 400L
                ) {
                    return false
                }
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
            val packed = "$cleanEpc,$rssi"
            val prefix = "$cleanEpc,"
            for (i in pendingTagEvents.indices.reversed()) {
                if (pendingTagEvents[i].startsWith(prefix)) {
                    pendingTagEvents[i] = packed
                    if (flushNow && !tagFlushScheduled) {
                        tagFlushScheduled = true
                        mainHandler.post { flushQueuedTagEvents() }
                    }
                    return
                }
            }
            // Cap batch size so unmatched floods cannot blow the Flutter event binder.
            // Never drop a matched search tag or a new inventory EPC (those
            // chips may stay quiet ~1 min after the first read).
            if (pendingTagEvents.size >= 300) {
                if (matchesSearchTag(cleanEpc) || inventoryScanMode) {
                    pendingTagEvents.removeAt(0)
                    droppedTagEvents++
                } else {
                    droppedTagEvents++
                    return
                }
            }
            pendingTagEvents.add(packed)
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

    /** Search is running. Its tone stays until [stopRfidInventory]. */
    private fun searchSessionActive(): Boolean =
        isScanning && !activeInventorySession && !trayModeEnabled && !r6ModeEnabled

    private fun stopSound(id: Int, force: Boolean = false) {
        if (!force && searchSessionActive()) return
        if (force) searchToneGeneration++
        val silence = Runnable {
            synchronized(soundLock) {
                val streamId = soundStreamIds.remove(id) ?: return@Runnable
                silenceStream(streamId)
            }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) silence.run() else mainHandler.post(silence)
    }

    private fun stopAllSounds(force: Boolean = false) {
        if (!force && searchSessionActive()) return
        // Flag first, on this thread, so a tag read cannot start another loop.
        searchSoundEnabled = false
        searchToneGeneration++
        val silence = Runnable { silenceMappedStreams() }
        if (Looper.myLooper() == Looper.getMainLooper()) silence.run() else mainHandler.post(silence)
    }

    private fun silenceMappedStreams() {
        val streamIds: List<Int>
        synchronized(soundLock) {
            streamIds = ArrayList(soundStreamIds.values)
            soundStreamIds.clear()
            bestSearchSoundId = -1
            lastSearchSoundId = -1
        }
        streamIds.forEach { silenceStream(it) }
    }

    /** Looping search tones ignore a plain stop. Mute, end the loop, pause, then stop. */
    private fun silenceStream(streamId: Int) {
        if (streamId == 0) return
        val pool = soundPool ?: return
        try {
            pool.setVolume(streamId, 0f, 0f)
        } catch (_: Throwable) {
        }
        try {
            pool.setLoop(streamId, 0)
        } catch (_: Throwable) {
        }
        try {
            pool.pause(streamId)
        } catch (_: Throwable) {
        }
        try {
            pool.stop(streamId)
        } catch (_: Throwable) {
        }
    }

    /** Silence the search tone once reads stop, without ending the search. */
    private val searchRangeWatch = object : Runnable {
        override fun run() {
            if (!searchSoundEnabled || !isScanning) return
            val last = lastSearchHitAt
            if (last != 0L && SystemClock.elapsedRealtime() - last >= 1000L) {
                silenceMappedStreams()
            }
            mainHandler.postDelayed(this, 400L)
        }
    }

    private fun armSearchRangeWatch() {
        mainHandler.removeCallbacks(searchRangeWatch)
        mainHandler.postDelayed(searchRangeWatch, 400L)
    }

    /**
     * Sparkle SearchViewModel RSSI → sound id buckets:
     * abs(rssi) <50 → fourty(4), <60 → sixty(2), <70 → found2(5), else barcodebeep(1).
     * The tone follows the tag's current range and stops when it leaves range.
     */
    private fun playRssiSearchSound(rssi: String) {
        if (!searchSoundEnabled || !isScanning) return
        val rssiAbs = try {
            kotlin.math.abs(rssi.trim().toDouble())
        } catch (_: Exception) {
            0.0
        }
        val id = when {
            rssiAbs > 0 && rssiAbs < 50 -> if (searchLedMulti) 5 else 4
            rssiAbs > 50 && rssiAbs < 60 -> 2
            rssiAbs > 60 && rssiAbs < 70 -> if (searchLedMulti) 4 else 5
            rssiAbs > 70 -> 1
            else -> -1
        }
        if (id == -1) return
        if (id == bestSearchSoundId) {
            keepSearchSound()
            return
        }
        val now = System.currentTimeMillis()
        if (bestSearchSoundId > 0 && now - lastSearchSoundPlayAt < searchSoundSwitchMinMs) {
            keepSearchSound()
            return
        }
        lastSearchSoundPlayAt = now
        if (searchSoundRank(id) <= 1) lastCloseSearchSoundAt = now
        if (bestSearchSoundId > 0 && bestSearchSoundId != id) {
            stopSound(bestSearchSoundId, force = true)
        }
        bestSearchSoundId = id
        lastSearchSoundId = id
        playSearchTone(id)
    }

    /** Restart the tone already reached if a gap silenced it. Never picks a weaker one. */
    private fun keepSearchSound() {
        if (!searchSoundEnabled || !isScanning) return
        val id = if (bestSearchSoundId > 0) bestSearchSoundId else lastSearchSoundId
        if (id <= 0) return
        if (soundStreamIds.containsKey(id)) return
        playSearchTone(id)
    }

    /**
     * Search tone loops until the user stops the search, or a closer/farther
     * RSSI bucket replaces it. Restarting it on every tag read was cutting it off.
     */
    private fun playSearchTone(id: Int) {
        if (!searchSoundEnabled || !isScanning) return
        if (soundStreamIds.containsKey(id)) return
        val generation = searchToneGeneration
        val play = Runnable {
            if (generation != searchToneGeneration || !searchSoundEnabled || !isScanning) return@Runnable
            playSearchToneNow(id, generation)
        }
        if (Looper.myLooper() == Looper.getMainLooper()) play.run() else mainHandler.post(play)
    }

    private fun playSearchToneNow(id: Int, generation: Int) {
        if (generation != searchToneGeneration || !searchSoundEnabled || !isScanning) return
        try {
            ensureSoundPool()
            val soundId = soundMap[id] ?: return
            if (soundId == 0) return
            synchronized(soundLock) {
                if (soundStreamIds.containsKey(id)) return
            }
            val maxVol = audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC)?.toFloat() ?: 1f
            val curVol = audioManager?.getStreamVolume(AudioManager.STREAM_MUSIC)?.toFloat() ?: 1f
            volumeRatio = if (maxVol > 0f) curVol / maxVol else 1f
            val streamId = soundPool?.play(
                soundId,
                volumeRatio,
                volumeRatio,
                1,
                -1,
                1f,
            ) ?: return
            // Stop can land while play() is in flight. A plain stop leaves loop=-1 running.
            if (generation != searchToneGeneration || !searchSoundEnabled || !isScanning) {
                silenceStream(streamId)
                return
            }
            synchronized(soundLock) {
                if (generation != searchToneGeneration || !searchSoundEnabled || !isScanning) {
                    silenceStream(streamId)
                    return
                }
                soundStreamIds[id] = streamId
            }
        } catch (e: Throwable) {
            e.printStackTrace()
        }
    }

    /** 0 = closest, 3 = farthest. Unmatched list swaps the 1st and 3rd tones. */
    private fun searchSoundRank(id: Int): Int {
        if (searchLedMulti) {
            return when (id) {
                5 -> 0
                2 -> 1
                4 -> 2
                1 -> 3
                else -> 4
            }
        }
        return when (id) {
            4 -> 0
            2 -> 1
            5 -> 2
            1 -> 3
            else -> 4
        }
    }

    companion object {
        private const val TAG = "HardwareController"
        private const val SEARCH_LED_WAIT = 0
        private const val SEARCH_LED_BLINK = 1
        private const val SEARCH_LED_DISCOVER = 2
        private const val SEARCH_LED_MAX = 8
        /** List chips remembered for blink. The radio filter itself still holds 8. */
        private const val SEARCH_LED_REMEMBER = 24
        /** Wait after the last newly-found tag so a pile of 3 is applied together. */
        private const val SEARCH_LED_GATHER_MS = 280L
        private const val SEARCH_LED_GATHER_MAX_MS = 800L
        /** EPC window so normal tags keep scanning. */
        private const val SEARCH_LED_SCAN_MS = 550L
        /** Keep LabelStock LEDs on, then return to EPC for other tags. */
        private const val SEARCH_LED_BLINK_MS = 1400L
        private const val SEARCH_LED_HIT_TIMEOUT_MS = 700L
        /** Field on, then off. Continuous LED inventory looks solid, so this pulse is the blink. */
        private const val LED_BLINK_ON_MS = 50L
        private const val LED_BLINK_OFF_MS = 50L
        private const val SEARCH_RADIO_EPC = 0
        private const val SEARCH_RADIO_FILTER = 1
        private const val SEARCH_RADIO_ALL = 2
    }
}
