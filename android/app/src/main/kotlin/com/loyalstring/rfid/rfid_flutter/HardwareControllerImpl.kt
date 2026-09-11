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
import java.util.HashMap
import java.util.HashSet
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
    private var foundLedGatherUntil = 0L
    private var foundLedGatherDeadline = 0L
    private var searchLedAppliedKey = ""
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
        val stripped = stripScanKey00(key)
        synchronized(searchTagLock) {
            searchTags.add(key)
            if (stripped.isNotEmpty()) searchTags.add(stripped)
        }
    }

    /** Demo Tag LED uses whatever getEPC() returns — not only 24/32 hex. */
    private fun isLedEpcHex(key: String): Boolean {
        if (key.length < 8 || key.length > 64 || key.length % 2 != 0) return false
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
        foundLedGatherUntil = 0L
        foundLedGatherDeadline = 0L
        searchLedAppliedKey = ""
    }

    private fun matchesSearchTag(cleanEpc: String): Boolean {
        synchronized(searchTagLock) {
            if (searchTags.isEmpty()) return false
            if (searchTags.contains(cleanEpc)) return true
            val stripped = stripScanKey00(cleanEpc)
            return stripped.isNotEmpty() && searchTags.contains(stripped)
        }
    }

    private var inventoryMediaPlayer: MediaPlayer? = null
    private val sessionUniqueEpcs = HashSet<String>()
    private var reconnectRunnable: Runnable? = null

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
                tagSetExecutor.execute {
                    synchronized(searchTagLock) {
                        searchTags.clear()
                        searchLedEpcs.clear()
                    }
                    resetSearchLedFoundState()
                    for (tag in tags) addSearchKey(tag)
                }
                result.success(true)
            }
            "addSearchTags" -> {
                val tags = ArrayList(call.argument<List<String>>("tags") ?: emptyList())
                tagSetExecutor.execute {
                    for (tag in tags) addSearchKey(tag)
                }
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
            if (r6ModeEnabled && !trayManager.isReallyConnected()) {
                if (trayManager.isConnecting) {
                    Log.i(TAG, "R6 BLE connect already in progress — skip")
                } else {
                    Executors.newSingleThreadExecutor().execute {
                        trayManager.connectAndWait(address, 28000L)
                    }
                }
            } else if (trayModeEnabled && !trayManager.isReallyConnected()) {
                if (trayManager.isConnecting) {
                    Log.i(TAG, "Tray BLE connect already in progress — skip")
                } else {
                    Executors.newSingleThreadExecutor().execute {
                        trayManager.connectAndWait(address, 28000L)
                    }
                }
            } else if (!trayManager.isReallyConnected()) {
                trayManager.connect(address)
            }
        } else {
            trayManager.disconnect()
        }
    }

    private fun scheduleBleReconnectIfNeeded() {
        val address = when {
            trayModeEnabled -> trayDeviceAddress
            r6ModeEnabled -> r6DeviceAddress
            else -> ""
        }
        if (address.isEmpty() || (!trayModeEnabled && !r6ModeEnabled)) return
        if (trayManager.isConnecting || trayManager.isReallyConnected()) return
        cancelBleReconnect()
        val runnable = Runnable {
            if ((trayModeEnabled || r6ModeEnabled) &&
                !trayManager.isReallyConnected() &&
                !trayManager.isConnecting &&
                address.isNotEmpty()
            ) {
                Executors.newSingleThreadExecutor().execute {
                    trayManager.connectAndWait(address, 28000L)
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
        map["connecting"] = trayModeEnabled && ::trayManager.isInitialized && trayManager.isConnecting
        map["address"] = trayDeviceAddress
        return map
    }

    private fun r6StatusMap(): HashMap<String, Any> {
        val map = HashMap<String, Any>()
        map["enabled"] = r6ModeEnabled
        map["connected"] = r6ModeEnabled && (trayManager.isReallyConnected() || trayManager.isConnected)
        map["address"] = r6DeviceAddress
        map["connecting"] = r6ModeEnabled && trayManager.isConnecting
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
        if (isScanning) {
            return true
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
                if (!linked) {
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
            try {
                uhf().setInventoryCallback(null)
            } catch (_: Throwable) {
            }
            // Same UART start as Scan Display. Do not EPC-filter the catalog
            // here — DB RFID often differs from the live chip EPC.
            uhf().prepareScan(power)
            if (inventory) {
                startInventoryLoopSound()
            } else if (playStartSound) {
                playSound(1, 0)
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
                uhf().prepareScan(power)
                started = uhf().startInventory()
                Log.i(TAG, "startInventory attempt=2 => $started")
            }
            if (!started) {
                Log.w(TAG, "startInventory failed — recoverHardware")
                if (uhf().recoverHardware()) {
                    uhf().prepareScan(power)
                    started = uhf().startInventory()
                    Log.i(TAG, "startInventory attempt=3 recover => $started")
                }
            }
            if (started) {
                isScanning = true
                startPollingThread(inventory, useTray = false)
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

    private fun startR6InventoryGuarded(power: Int, inventory: Boolean, playStartSound: Boolean = true): Boolean {
        scanningPermitted = true
        if (isScanning) {
            return true
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
            if (!linked) {
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
                Log.i(TAG, "Tray startInventory attempt=${attempt + 1} => $started")
                if (started) break
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
            isScanning = true
            startPollingThread(inventory, useTray = true)
            true
        } catch (e: Throwable) {
            e.printStackTrace()
            isScanning = false
            stopInventoryLoopSound()
            false
        }
    }

    /** Search starts EPC inventory (same as Scan Display). Small 1–8 lists get demo LED at start. */
    private fun applySearchLedBlinkModeIfNeeded(inventory: Boolean) {
        if (inventory || trayModeEnabled || r6ModeEnabled) return
        resetSearchLedFoundState()
    }

    private fun searchLedKey(epcs: Collection<String>): String =
        epcs.sorted().joinToString(",")

    private fun ledEpcOf(cleanEpc: String): String? {
        if (cleanEpc.length < 4) return null
        return cleanEpc
    }

    /** When a search tag is matched (progress/%), queue that live chip EPC for LED. */
    private fun noteFoundSearchLed(cleanEpc: String) {
        if (activeInventorySession || trayModeEnabled || r6ModeEnabled) return
        val epc = ledEpcOf(cleanEpc) ?: return
        val now = SystemClock.elapsedRealtime()
        synchronized(foundLedLock) {
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
        if (searchLedApplyBusy || uartPollPaused) return
        if (!isScanning || activeInventorySession || trayModeEnabled || r6ModeEnabled) return
        val now = SystemClock.elapsedRealtime()
        var wantBlink = false
        var epcs: List<String> = emptyList()
        synchronized(foundLedLock) {
            epcs = ArrayList(foundLedEpcs.keys)
            if (epcs.isEmpty()) return
            if (searchLedKey(epcs) == searchLedAppliedKey) return
            if (foundLedGatherUntil <= 0L) return
            val quietElapsed = now >= foundLedGatherUntil
            val maxElapsed = foundLedGatherDeadline > 0L && now >= foundLedGatherDeadline
            wantBlink = quietElapsed || maxElapsed
        }
        if (wantBlink) requestSearchLedHandoff(epcs)
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

    /**
     * uhf-uart-demo Tag LED: park poller, stop, setFilter(matched EPCs),
     * MODE_LED_TAG, start. Do not call prepareScan/setEPCMode here — that turns the LED off.
     */
    private fun applySearchLedHandoff(epcs: List<String>) {
        if (!isScanning || activeInventorySession || trayModeEnabled || r6ModeEnabled) return
        if (epcs.isEmpty()) return
        if (!pollerActive || !waitUntilPollerParked(500L)) {
            uartPollPaused = false
            searchLedFailBackoff()
            return
        }
        try {
            uhf().stopInventory()
            try {
                Thread.sleep(80L)
            } catch (_: InterruptedException) {
            }
            if (!isScanning) return
            uhf().setPower(lastScanPower)
            val filtered = uhf().applyLedTagBlinkMode(epcs)
            Log.i(TAG, "Search LED tag mode epcs=${epcs.size} => $filtered")
            if (!filtered || !isScanning) {
                uhf().setPower(lastScanPower)
                uhf().startInventory()
                searchLedFailBackoff()
                return
            }
            var started = uhf().startInventory()
            if (!started && isScanning) {
                try {
                    Thread.sleep(80L)
                } catch (_: InterruptedException) {
                }
                started = uhf().startInventory()
            }
            if (!started) {
                Log.w(TAG, "Search LED start failed — resume without killing LED mode")
                uhf().setPower(lastScanPower)
                started = uhf().startInventory()
                if (!started) {
                    uhf().prepareScan(lastScanPower)
                    uhf().startInventory()
                    searchLedFailBackoff()
                    return
                }
            }
            searchLedAppliedKey = searchLedKey(epcs)
            searchLedPhase = SEARCH_LED_BLINK
            foundLedGatherUntil = 0L
            foundLedGatherDeadline = 0L
        } catch (e: Throwable) {
            Log.w(TAG, "Search LED handoff failed: ${e.message}")
            try {
                if (isScanning) {
                    uhf().setPower(lastScanPower)
                    uhf().startInventory()
                }
            } catch (_: Throwable) {
            }
            searchLedFailBackoff()
        }
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
        try {
            uhfFacade?.setInventoryCallback(null)
        } catch (_: Throwable) {
        }
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
        if (!inventory && matchesSearchTag(cleanEpc)) {
            playRssiSearchSound(rssi)
            noteFoundSearchLed(cleanEpc)
        }

        if (!shouldEmitTagToFlutter(cleanEpc, rssi)) {
            return
        }
        queueTagEvent(cleanEpc, rssi)
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

    private fun queueTagEvent(cleanEpc: String, rssi: String) {
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
                mainHandler.postDelayed({ flushQueuedTagEvents() }, tagFlushDelayMs)
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
        private const val SEARCH_LED_MAX = 8
        /** Wait after the last newly-found tag so a pile of 3 is applied together. */
        private const val SEARCH_LED_GATHER_MS = 50L
        private const val SEARCH_LED_GATHER_MAX_MS = 200L
    }
}
