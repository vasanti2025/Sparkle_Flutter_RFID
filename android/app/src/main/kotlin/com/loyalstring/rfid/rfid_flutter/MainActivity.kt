package com.loyalstring.rfid.rfid_flutter

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.SoundPool
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import androidx.core.content.ContextCompat
import com.rscja.deviceapi.RFIDWithUHFUART
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.HashMap
import java.util.HashSet

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.loyalstring.rfid/uhf"
    private val EVENT_CHANNEL = "com.loyalstring.rfid/tags"

    private var mReader: RFIDWithUHFUART? = null
    private var isScanning = false
    private var executorService: ExecutorService? = null
    private var eventSink: EventChannel.EventSink? = null

    // Sound resources
    private var soundPool: SoundPool? = null
    private val soundMap = HashMap<Int, Int>()
    private val soundStreamIds = HashMap<Int, Int>()
    private var lastSoundId = -1
    private var lastSoundPlayAt = 0L

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
    private val emitDedupMs = 250L
    private val tagFlushDelayMs = 50L

    // Looping inventory scan sound (matches Kotlin SoundPlayer)
    private var inventoryMediaPlayer: MediaPlayer? = null

    private var trayModeEnabled = false
    private var trayDeviceAddress = ""
    private lateinit var trayManager: TrayReaderManager
    private var activeInventorySession = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        initSoundPool()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initReaderHardware()
        trayManager = TrayReaderManager(
            this,
            onTagRead = { epc, rssi ->
                // Accept callback tags whenever inventory is running (same as buffer poll path).
                if (isScanning) {
                    handleTagRead(epc, rssi, activeInventorySession)
                }
            },
            onConnectionChange = { connected, _ ->
                mainHandler.post {
                    eventSink?.success(if (connected) "TRAY_CONNECTED" else "TRAY_DISCONNECTED")
                }
            },
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initReader" -> {
                    result.success(initReaderHardware())
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
                    val ok = startRfidInventory(power, inventory)
                    result.success(ok)
                }
                "stopScanning" -> {
                    val ok = stopRfidInventory()
                    result.success(ok)
                }
                "setPower" -> {
                    val power = call.argument<Int>("power") ?: 5
                    result.success(setReaderPower(power))
                }
                "isSupported" -> {
                    result.success(checkIsSupported())
                }
                "setSearchTags" -> {
                    val tags = call.argument<List<String>>("tags") ?: emptyList()
                    searchTags.clear()
                    matchEpcs.clear()
                    searchTags.addAll(tags.map { it.trim().uppercase() })
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
                    playBeepSound()
                    result.success(true)
                }
                "clearMatchEpcs" -> {
                    matchEpcs.clear()
                    result.success(true)
                }
                "clearSearchTags" -> {
                    searchTags.clear()
                    for (streamId in soundStreamIds.values) {
                        soundPool?.stop(streamId)
                    }
                    soundStreamIds.clear()
                    lastSoundId = -1
                    result.success(true)
                }
                "clearInventoryScope" -> {
                    inventoryScopeEpcs.clear()
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
                    trayModeEnabled = call.argument<Boolean>("enabled") ?: false
                    val address = call.argument<String>("address")?.trim().orEmpty()
                    trayDeviceAddress = address
                    if (trayModeEnabled && address.isNotEmpty()) {
                        trayManager.init()
                        trayManager.connect(address)
                    } else {
                        trayManager.disconnect()
                    }
                    result.success(trayStatusMap())
                }
                "listBondedBluetoothDevices" -> {
                    result.success(listBondedBluetoothDevices())
                }
                "getTrayStatus" -> {
                    result.success(trayStatusMap())
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    private fun checkIsSupported(): Boolean {
        // UART gun OR BLE tray SDK — either is enough to use native RFID.
        val uartOk = try {
            RFIDWithUHFUART.getInstance() != null
        } catch (_: Throwable) {
            false
        }
        if (uartOk) return true
        return try {
            com.rscja.deviceapi.RFIDWithUHFBLE.getInstance() != null
        } catch (_: Throwable) {
            false
        }
    }

    private fun initReaderHardware(): Boolean {
        return try {
            if (mReader == null) {
                mReader = RFIDWithUHFUART.getInstance()
            }
            mReader?.init(this) ?: false
        } catch (e: Throwable) {
            e.printStackTrace()
            false
        }
    }

    private fun setReaderPower(power: Int): Boolean {
        return try {
            if (trayModeEnabled) {
                trayManager.setPower(power)
            } else {
                mReader?.setPower(power) ?: false
            }
        } catch (_: Throwable) {
            false
        }
    }

    private fun useTrayReader(): Boolean {
        return trayModeEnabled && trayManager.isConnected
    }

    private fun trayStatusMap(): HashMap<String, Any> {
        val map = HashMap<String, Any>()
        map["enabled"] = trayModeEnabled
        map["connected"] = trayManager.isConnected
        map["address"] = trayDeviceAddress
        return map
    }

    private fun hasBluetoothPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            @Suppress("DEPRECATION")
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    private fun bluetoothAdapter(): BluetoothAdapter? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            manager?.adapter
        } else {
            @Suppress("DEPRECATION")
            BluetoothAdapter.getDefaultAdapter()
        }
    }

    private fun listBondedBluetoothDevices(): List<Map<String, String>> {
        if (!hasBluetoothPermission()) return emptyList()
        val adapter = bluetoothAdapter() ?: return emptyList()
        if (!adapter.isEnabled) return emptyList()
        return adapter.bondedDevices.mapNotNull { device ->
            val address = device.address?.trim().orEmpty()
            if (address.isEmpty()) return@mapNotNull null
            val name = device.name?.trim()?.takeIf { it.isNotEmpty() } ?: "Bluetooth Device"
            mapOf("name" to name, "address" to address)
        }.sortedBy { it["name"]?.lowercase() }
    }

    private fun haltScan() {
        scanningPermitted = false
        inventoryScanMode = false
        inventoryScopeEpcs.clear()
        stopInventoryLoopSound()
    }

    private fun startRfidInventory(power: Int, inventory: Boolean): Boolean {
        if (!scanningPermitted) {
            return false
        }
        if (isScanning) {
            return true
        }
        activeInventorySession = inventory
        // Tray mode must never fall back to UART gun — that is why tags on the tray
        // appeared "not scanning" while SparklePOS (tray-only) worked.
        if (trayModeEnabled) {
            if (!trayManager.isConnected) {
                return false
            }
            return startTrayInventory(power, inventory)
        }
        return try {
            initReaderHardware()
            mReader?.apply {
                setPower(power)
                setTagFocus(false)
                setFastID(false)
                setDynamicDistance(0)
            }
            drainStaleBuffer()
            if (inventory) {
                startInventoryLoopSound()
            }
            val started = mReader?.startInventoryTag() ?: false
            if (started) {
                isScanning = true
                if (inventory) {
                    playBeepSound()
                }
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

    private fun startTrayInventory(power: Int, inventory: Boolean): Boolean {
        return try {
            // Match SparklePOS: do not hard-fail on setPower; BLE tray often ignores it.
            try {
                trayManager.setPower(power)
            } catch (_: Throwable) {
            }
            trayManager.drainBuffer()
            if (inventory) {
                startInventoryLoopSound()
            }
            // Mark scanning before startInventory so IUHFInventoryCallback tags are not dropped.
            isScanning = true
            val started = trayManager.startInventory()
            if (started) {
                if (inventory) {
                    playBeepSound()
                }
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

    private fun stopRfidInventory(): Boolean {
        searchTags.clear()
        matchEpcs.clear()
        inventoryScanMode = false
        scanningPermitted = false
        inventoryScopeEpcs.clear()
        for (streamId in soundStreamIds.values) {
            soundPool?.stop(streamId)
        }
        soundStreamIds.clear()
        lastSoundId = -1
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
        return try {
            if (trayModeEnabled) {
                trayManager.stopInventory()
            } else {
                mReader?.stopInventory() ?: false
            }
        } catch (e: Throwable) {
            e.printStackTrace()
            false
        }
    }

    private fun drainStaleBuffer() {
        var drained = 0
        while (drained < 64) {
            val tag = mReader?.readTagFromBuffer() ?: break
            if (tag.epc.isNullOrBlank()) break
            drained++
        }
    }

    private fun startPollingThread(inventory: Boolean, useTray: Boolean) {
        executorService = Executors.newSingleThreadExecutor()
        executorService?.execute {
            while (isScanning) {
                try {
                    var tagInfo = if (useTray) {
                        trayManager.readTagFromBuffer()
                    } else {
                        mReader?.readTagFromBuffer()
                    }
                    if (tagInfo == null) {
                        Thread.sleep(1)
                        continue
                    }

                    do {
                        val epc = tagInfo?.epc ?: tagInfo?.getEPC()
                        if (!epc.isNullOrBlank()) {
                            val cleanEpc = epc.trim().uppercase()
                            val rssi = tagInfo?.rssi ?: ""
                            handleTagRead(cleanEpc, rssi, inventory)
                        }
                        tagInfo = if (useTray) {
                            trayManager.readTagFromBuffer()
                        } else {
                            mReader?.readTagFromBuffer()
                        }
                    } while (tagInfo != null && isScanning)
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
        if (shouldEmitTagToFlutter(cleanEpc)) {
            queueTagEvent(cleanEpc, rssi)
        }

        if (!inventory) {
            when {
                searchTags.isNotEmpty() -> {
                    if (searchTags.contains(cleanEpc)) {
                        playSearchSoundForRssi(rssi)
                    }
                }
                matchEpcs.isNotEmpty() -> {
                    if (matchEpcs.contains(cleanEpc)) {
                        playBeepSound()
                    }
                }
                else -> playBeepSound()
            }
        }
    }

    private fun shouldEmitTagToFlutter(cleanEpc: String): Boolean {
        // SparklePOS tray path emits every EPC; product matching happens in Flutter.
        // Native matchEpcs filtering was silently dropping tray tags not yet in local DB.
        if (!trayModeEnabled) {
            if (inventoryScanMode) {
                if (inventoryScopeEpcs.isNotEmpty() && !inventoryScopeEpcs.contains(cleanEpc)) {
                    return false
                }
            } else {
                when {
                    searchTags.isNotEmpty() -> if (!searchTags.contains(cleanEpc)) return false
                    matchEpcs.isNotEmpty() -> if (!matchEpcs.contains(cleanEpc)) return false
                }
            }
        }
        val now = System.currentTimeMillis()
        synchronized(recentEmitAt) {
            val last = recentEmitAt[cleanEpc] ?: 0L
            if (now - last < emitDedupMs) return false
            recentEmitAt[cleanEpc] = now
            if (recentEmitAt.size > 12000) {
                recentEmitAt.clear()
            }
        }
        return true
    }

    private fun queueTagEvent(cleanEpc: String, rssi: String) {
        synchronized(pendingTagLock) {
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

    /** EventSink must run on main thread — background posts were dropping all tags in Flutter. */
    private fun emitTagEvent(cleanEpc: String, rssi: String) {
        queueTagEvent(cleanEpc, rssi)
    }

    private fun startInventoryLoopSound() {
        try {
            if (inventoryMediaPlayer == null) {
                val resId = resources.getIdentifier("barcodebeep", "raw", packageName)
                if (resId != 0) {
                    inventoryMediaPlayer = MediaPlayer.create(this, resId)
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

    private fun playSearchSoundForRssi(rssi: String) {
        val rssiAbs = try {
            Math.abs(rssi.trim().toDouble())
        } catch (_: Exception) {
            0.0
        }
        val id = when {
            rssiAbs > 0 && rssiAbs <= 50 -> 4
            rssiAbs > 50 && rssiAbs <= 60 -> 2
            rssiAbs > 60 && rssiAbs <= 70 -> 5
            rssiAbs > 70 -> 1
            else -> -1
        }
        if (id != -1) {
            playSearchSound(id)
        }
    }

    private fun initSoundPool() {
        try {
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            soundPool = SoundPool.Builder()
                .setMaxStreams(10)
                .setAudioAttributes(audioAttributes)
                .build()

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
        val resId = resources.getIdentifier(name, "raw", packageName)
        return if (resId != 0) {
            soundPool?.load(this, resId, 1) ?: 0
        } else {
            0
        }
    }

    private fun playSearchSound(id: Int) {
        val now = System.currentTimeMillis()
        if (id != lastSoundId || now - lastSoundPlayAt >= 15L) {
            lastSoundPlayAt = now
            for (streamId in soundStreamIds.values) {
                soundPool?.stop(streamId)
            }
            soundStreamIds.clear()
            lastSoundId = id
            val soundId = soundMap[id] ?: return
            if (soundId != 0) {
                val streamId = soundPool?.play(soundId, 1.0f, 1.0f, 1, 0, 1.0f) ?: 0
                if (streamId != 0) {
                    soundStreamIds[id] = streamId
                }
            }
        }
    }

    private fun playBeepSound() {
        val soundId = soundMap[1] ?: return
        if (soundId != 0) {
            soundPool?.play(soundId, 1.0f, 1.0f, 1, 0, 1.0f)
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == 293 || keyCode == 280 || keyCode == 139) {
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN) {
            val keyCode = event.keyCode
            if (keyCode == 293 || keyCode == 280 || keyCode == 139) {
                if (event.repeatCount == 0) {
                    runOnUiThread {
                        eventSink?.success("TRIGGER_CLICK")
                    }
                }
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onDestroy() {
        stopRfidInventory()
        if (::trayManager.isInitialized) {
            trayManager.disconnect()
        }
        soundPool?.release()
        soundPool = null
        super.onDestroy()
    }
}
