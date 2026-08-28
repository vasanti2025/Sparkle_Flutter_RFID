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
    private val searchSoundMinIntervalMs = 15L

    /** Sparkle SearchViewModel continuous tag LED blink (Bank_RESERVED read). */
    @Volatile private var blinkEpc: String? = null
    private var blinkExecutor: ExecutorService? = null
    private val blinkLedVisibleMs = 50L
    private val blinkCyclePauseMs = 200L
    private val blinkLock = Any()

    private var searchTags = HashSet<String>()
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
    /** Search proximity needs fresher RSSI than generic product-scan dedup. */
    private val searchEmitDedupMs = 80L
    private val tagFlushDelayMs = 50L

    private fun normalizeScanKey(raw: String): String =
        raw.trim().uppercase().replace(Regex("\\s+"), "")

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
        stopRfidInventory()
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
                    Executors.newSingleThreadExecutor().execute {
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
                Executors.newSingleThreadExecutor().execute {
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
                result.success(stopRfidInventory())
            }
            "setPower" -> {
                val power = call.argument<Int>("power") ?: 5
                result.success(setReaderPower(power))
            }
            "isSupported" -> {
                // Optimistic — real init happens on scan. Never call DeviceAPI here.
                result.success(true)
            }
            "setSearchTags" -> {
                val tags = call.argument<List<String>>("tags") ?: emptyList()
                searchTags.clear()
                matchEpcs.clear()
                searchTags.addAll(tags.map { normalizeScanKey(it) }.filter { it.isNotEmpty() })
                result.success(true)
            }
            "addSearchTags" -> {
                val tags = call.argument<List<String>>("tags") ?: emptyList()
                searchTags.addAll(tags.map { normalizeScanKey(it) }.filter { it.isNotEmpty() })
                result.success(true)
            }
            "setMatchEpcs" -> {
                val epcs = call.argument<List<String>>("epcs") ?: emptyList()
                searchTags.clear()
                matchEpcs.clear()
                matchEpcs.addAll(epcs.map { it.trim().uppercase() }.filter { it.isNotEmpty() })
                result.success(true)
            }
            "setInventoryScanMode" -> {
                inventoryScanMode = call.argument<Boolean>("enabled") ?: false
                if (inventoryScanMode) {
                    searchTags.clear()
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
                searchTags.clear()
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
            Executors.newSingleThreadExecutor().execute {
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
        if (!scanningPermitted) {
            return false
        }
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
            // Ensure UART is up before prepare/start (10k Dart heap can delay prior warm).
            if (!uhf().initHardware()) {
                Log.e(TAG, "startRfidInventory: initHardware failed")
                stopInventoryLoopSound()
                return false
            }
            uhf().prepareScan(power)
            drainStaleBuffer()
            if (inventory) {
                startInventoryLoopSound()
            } else if (playStartSound) {
                playSound(1, 0)
            }
            var started = false
            // Up to 4 attempts — Chainway often returns false if prior session
            // was not fully released under heavy Flutter GC (10k inventory).
            for (attempt in 0 until 4) {
                if (started) break
                if (attempt > 0) {
                    try {
                        uhf().stopInventory()
                    } catch (_: Throwable) {
                    }
                    try {
                        Thread.sleep(100L * attempt)
                    } catch (_: InterruptedException) {
                    }
                    drainStaleBuffer()
                    uhf().prepareScan(power)
                }
                started = uhf().startInventory()
                Log.i(TAG, "startInventory attempt=${attempt + 1} => $started")
            }
            if (started) {
                isScanning = true
                startPollingThread(inventory, useTray = false)
            } else {
                stopInventoryLoopSound()
            }
            started
        } catch (e: Throwable) {
            e.printStackTrace()
            stopInventoryLoopSound()
            false
        }
    }

    private fun startR6InventoryGuarded(power: Int, inventory: Boolean, playStartSound: Boolean = true): Boolean {
        if (!scanningPermitted) {
            return false
        }
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

    private fun stopRfidInventory(): Boolean {
        // searchTags / matchEpcs cleared via clearSearchTags / clearMatchEpcs from Dart.
        stopBlinkingEpc()
        inventoryScanMode = false
        scanningPermitted = false
        inventoryScopeEpcs.clear()
        sessionUniqueEpcs.clear()
        stopAllSounds()
        lastSearchSoundId = -1
        stopInventoryLoopSound()

        isScanning = false
        activeInventorySession = false
        executorService?.shutdownNow()
        executorService = null
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
        val useBle = useBleReader()
        java.util.concurrent.Executors.newSingleThreadExecutor().execute {
            var stopped = false
            for (attempt in 0 until 3) {
                if (stopped) break
                try {
                    stopped = if (useBle) {
                        trayManager.stopInventory()
                    } else {
                        uhfFacade?.stopInventory() ?: false
                    }
                } catch (_: Throwable) {}
                if (!stopped) {
                    try { Thread.sleep(50L) } catch (_: InterruptedException) {}
                }
            }
        }
        return true
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
        executorService = Executors.newSingleThreadExecutor()
        executorService?.execute {
            while (isScanning) {
                try {
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
                        } while (tagInfo != null && isScanning)
                    } else {
                        var pair = uhf().readTagFromBuffer()
                        if (pair == null) {
                            Thread.sleep(1)
                            continue
                        }
                        do {
                            val cleanEpc = normalizeScanKey(pair!!.first)
                            if (cleanEpc.isNotEmpty()) {
                                handleTagRead(cleanEpc, pair.second, inventory)
                            }
                            pair = uhf().readTagFromBuffer()
                        } while (pair != null && isScanning)
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
        }
    }

    private fun handleTagRead(cleanEpc: String, rssi: String, inventory: Boolean) {
        // Sparkle SearchViewModel: RSSI proximity tones + tag LED on every matched buffer read.
        if (!inventory && searchTags.isNotEmpty() && searchTags.contains(cleanEpc)) {
            playRssiSearchSound(rssi)
            updateSearchLedBlink(cleanEpc, rssi)
        }

        if (!shouldEmitTagToFlutter(cleanEpc, rssi)) {
            return
        }
        queueTagEvent(cleanEpc, rssi)
    }

    /**
     * Sparkle convertRssiToProximity + LED gate: blink while proximity > 0 for matched EPC.
     * Handheld UART only (tag LED via Reserved-bank read); BLE tray/R6 has no tag LED path.
     */
    private fun updateSearchLedBlink(cleanEpc: String, rssi: String) {
        if (trayModeEnabled || r6ModeEnabled) return
        val proximity = rssiToProximityPercent(rssi)
        // Blink only when very close — otherwise LED cycle stops inventory and stalls RSSI updates.
        if (proximity >= 70) {
            startContinuousBlink(cleanEpc)
        } else if (blinkEpc == cleanEpc) {
            stopBlinkingEpc()
        }
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

    /**
     * Sparkle SearchViewModel.startContinuousBlink — stop inventory, read Reserved bank
     * (tag LED flashes), restart inventory; repeat while search is active.
     */
    private fun startContinuousBlink(epc: String) {
        synchronized(blinkLock) {
            if (blinkEpc == epc && blinkExecutor != null && !(blinkExecutor!!.isShutdown)) {
                return
            }
            stopBlinkingEpcLocked()
            blinkEpc = epc
            val target = epc
            val power = lastScanPower
            blinkExecutor = Executors.newSingleThreadExecutor()
            blinkExecutor?.execute {
                while (!Thread.currentThread().isInterrupted &&
                    isScanning &&
                    !activeInventorySession &&
                    blinkEpc == target
                ) {
                    try {
                        uhfFacade?.stopInventory()
                        if (!isScanning || blinkEpc != target) break
                        uhfFacade?.readReservedBankForLed(target)
                        Thread.sleep(blinkLedVisibleMs)
                        if (!isScanning || blinkEpc != target) break
                        uhfFacade?.prepareScan(power)
                        uhfFacade?.startInventory()
                    } catch (e: InterruptedException) {
                        break
                    } catch (e: Exception) {
                        Log.e(TAG, "Search LED blink error: ${e.message}", e)
                    }
                    try {
                        Thread.sleep(blinkCyclePauseMs)
                    } catch (_: InterruptedException) {
                        break
                    }
                }
            }
        }
    }

    private fun stopBlinkingEpc() {
        synchronized(blinkLock) {
            stopBlinkingEpcLocked()
        }
    }

    private fun stopBlinkingEpcLocked() {
        blinkEpc = null
        try {
            blinkExecutor?.shutdownNow()
        } catch (_: Throwable) {
        }
        blinkExecutor = null
    }

    private fun shouldEmitTagToFlutter(cleanEpc: String, rssi: String = ""): Boolean {
        if (!trayModeEnabled && !r6ModeEnabled) {
            if (inventoryScanMode) {
                // Sparkle BulkViewModel: all inventory tags flow to the app;
                // matching uses filteredDbEpcSet in Flutter. Native scope filtering
                // dropped every tag when DB EPC ≠ chip EPC (looked like scan broken).
                if (matchEpcs.isNotEmpty() && !matchEpcs.contains(cleanEpc)) return false
            } else {
                when {
                    searchTags.isNotEmpty() -> if (!searchTags.contains(cleanEpc)) return false
                    matchEpcs.isNotEmpty() -> if (!matchEpcs.contains(cleanEpc)) return false
                }
            }
        }
        val now = System.currentTimeMillis()
        val isSearchTag = searchTags.isNotEmpty() && searchTags.contains(cleanEpc)
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
            if (pendingTagEvents.size >= 300) return
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
     */
    private fun playRssiSearchSound(rssi: String) {
        val rssiAbs = try {
            kotlin.math.abs(rssi.trim().toDouble())
        } catch (_: Exception) {
            0.0
        }
        val id = when {
            rssiAbs > 0 && rssiAbs < 50 -> 4
            rssiAbs > 50 && rssiAbs < 60 -> 2
            rssiAbs > 60 && rssiAbs < 70 -> 5
            rssiAbs > 70 -> 1
            else -> -1
        }
        if (id == -1) return
        val now = System.currentTimeMillis()
        if (id != lastSearchSoundId || now - lastSearchSoundPlayAt >= searchSoundMinIntervalMs) {
            lastSearchSoundPlayAt = now
            if (lastSearchSoundId > 0) {
                stopSound(lastSearchSoundId)
            }
            lastSearchSoundId = id
            playSound(id, 0)
        }
    }

    companion object {
        private const val TAG = "HardwareController"
    }
}
