package com.loyalstring.rfid.rfid_flutter

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.Context
import android.os.SystemClock
import android.util.Log
import com.rscja.deviceapi.RFIDWithUHFBLE
import com.rscja.deviceapi.entity.UHFTAGInfo
import com.rscja.deviceapi.interfaces.ConnectionStatus
import com.rscja.deviceapi.interfaces.ConnectionStatusCallback
import com.rscja.deviceapi.interfaces.IUHFInventoryCallback
import com.rscja.deviceapi.interfaces.KeyEventCallback
import com.rscja.deviceapi.interfaces.ScanBTCallback
import java.util.Collections
import java.util.LinkedHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Chainway BLE UHF (tray + R6 sled) via [RFIDWithUHFBLE].
 * R6 is a display-less Bluetooth sled — phone app shows all scan results.
 */
class TrayReaderManager(
    private val context: Context,
    private val onTagRead: (epc: String, rssi: String) -> Unit,
    private val onConnectionChange: (connected: Boolean, message: String?) -> Unit,
    private val onKeyEvent: ((down: Boolean, keyCode: Int) -> Unit)? = null,
) {
    companion object {
        private const val TAG = "TrayReaderManager"
        private const val CONNECT_GUARD_MS = 12_000L
    }

    private var reader: RFIDWithUHFBLE? = null
    private var initialized = false
    private var currentAddress: String = ""
    private val discoveryRunning = AtomicBoolean(false)
    private val connectLatch = AtomicReference<CountDownLatch?>(null)

    @Volatile
    private var connectStartedAtMs: Long = 0L

    @Volatile
    private var suppressDisconnectNotify: Boolean = false

    /**
     * Strong reference — Chainway SDK may drop anonymous callbacks.
     * Must be (re)bound after [RFIDWithUHFBLE.init] and again on CONNECTED
     * so the R6 sled trigger button keeps delivering key events.
     */
    private val keyCallback = object : KeyEventCallback {
        override fun onKeyDown(keyCode: Int) {
            Log.i(TAG, "R6 keyDown code=$keyCode")
            onKeyEvent?.invoke(true, keyCode)
        }

        override fun onKeyUp(keyCode: Int) {
            Log.i(TAG, "R6 keyUp code=$keyCode")
            onKeyEvent?.invoke(false, keyCode)
        }
    }

    private fun bindKeyCallback() {
        try {
            val sdk = reader
            if (sdk == null) {
                Log.w(TAG, "bindKeyCallback skipped — reader null")
                return
            }
            sdk.setKeyEventCallback(keyCallback)
            Log.i(TAG, "KeyEventCallback bound status=${sdkStatus()}")
        } catch (e: Throwable) {
            Log.e(TAG, "setKeyEventCallback failed", e)
        }
    }

    fun bindKeyCallbackNow() {
        bindKeyCallback()
    }

    /** Re-bind after CONNECTED — SDK internal reader may not be ready instantly. */
    fun rebindKeyCallbackDelayed() {
        bindKeyCallback()
        // Chainway BLE stack sometimes installs key routing after GATT services settle.
        Thread {
            try {
                SystemClock.sleep(400)
                bindKeyCallback()
                SystemClock.sleep(800)
                bindKeyCallback()
            } catch (_: InterruptedException) {
            }
        }.start()
    }

    /** Single persistent callback — matches Chainway / R6 sample usage. */
    private val btStatus = object : ConnectionStatusCallback<Any> {
        override fun getStatus(status: ConnectionStatus?, device: Any?) {
            val name = status?.name ?: "null"
            Log.i(TAG, "BLE status=$name address=$currentAddress connecting=$isConnecting")
            when (status) {
                ConnectionStatus.CONNECTED -> {
                    isConnecting = false
                    isConnected = true
                    suppressDisconnectNotify = false
                    connectStartedAtMs = 0L
                    try {
                        reader?.setBeep(true)
                    } catch (_: Throwable) {
                    }
                    // R6 trigger keys only work after GATT is up — rebind with retries.
                    rebindKeyCallbackDelayed()
                    connectLatch.get()?.countDown()
                    onConnectionChange(true, name)
                }
                ConnectionStatus.CONNECTING -> {
                    isConnecting = true
                }
                ConnectionStatus.DISCONNECTED -> {
                    isConnected = false
                    // After a soft reconnect, SDK often emits DISCONNECTED once — do not
                    // treat that as a finished handshake, and do not storm auto-reconnect.
                    if (suppressDisconnectNotify) {
                        Log.i(TAG, "Suppressing DISCONNECTED notify during reconnect")
                        return
                    }
                    if (isConnecting) {
                        // Real failure while opening GATT — clear stuck "connecting".
                        val elapsed = SystemClock.elapsedRealtime() - connectStartedAtMs
                        if (connectStartedAtMs > 0L && elapsed > 1500L) {
                            Log.w(TAG, "Connect failed (DISCONNECTED after ${elapsed}ms)")
                            isConnecting = false
                            connectStartedAtMs = 0L
                            connectLatch.get()?.countDown()
                            onConnectionChange(false, name)
                        } else {
                            Log.i(TAG, "Ignoring early DISCONNECTED during connect open")
                        }
                        return
                    }
                    onConnectionChange(false, name)
                }
                else -> Unit
            }
        }
    }

    @Volatile
    var isConnected: Boolean = false
        private set

    @Volatile
    var isConnecting: Boolean = false
        private set

    fun init(): Boolean {
        return try {
            if (reader == null) {
                reader = RFIDWithUHFBLE.getInstance()
            }
            reader?.setSupportRssi(true)
            reader?.setInventoryCallback(IUHFInventoryCallback { info ->
                handleTagInfo(info)
            })
            // Keep a stable status listener (also passed into connect()).
            reader?.setConnectionStatusCallback(btStatus)
            if (!initialized) {
                // Application context is more stable for Chainway BLE SDK lifecycle.
                val ok = reader?.init(context.applicationContext) ?: false
                initialized = ok
                Log.i(TAG, "UHFBLE init=$ok")
                // Chainway sample: bind key callback AFTER init (init can clear it).
                bindKeyCallback()
                return ok
            }
            // Already initialized — keep callback registered (e.g. after reconnect).
            bindKeyCallback()
            true
        } catch (e: Throwable) {
            Log.e(TAG, "init failed", e)
            false
        }
    }

    private fun handleTagInfo(info: UHFTAGInfo?) {
        if (info == null) return
        val epc = info.epc?.trim()?.uppercase()
            ?: info.getEPC()?.trim()?.uppercase()
        if (epc.isNullOrBlank()) return
        val rssi = info.rssi ?: ""
        onTagRead(epc, rssi)
    }

    private fun stopBtDiscoveryQuietly() {
        try {
            reader?.stopScanBTDevices()
        } catch (_: Throwable) {
        }
        discoveryRunning.set(false)
    }

    private fun sdkStatus(): ConnectionStatus? {
        return try {
            reader?.connectStatus
        } catch (_: Throwable) {
            null
        }
    }

    private fun connectElapsedMs(): Long {
        val start = connectStartedAtMs
        if (start <= 0L) return 0L
        return (SystemClock.elapsedRealtime() - start).coerceAtLeast(0L)
    }

    private fun markConnecting() {
        isConnecting = true
        if (connectStartedAtMs <= 0L) {
            connectStartedAtMs = SystemClock.elapsedRealtime()
        }
    }

    private fun clearStuckConnecting(reason: String) {
        if (!isConnecting) return
        Log.w(TAG, "Clearing stuck connecting: $reason")
        isConnecting = false
        connectStartedAtMs = 0L
        suppressDisconnectNotify = false
        connectLatch.get()?.countDown()
    }

    /**
     * Soft reset half-open GATT without notifying Flutter reconnect (avoids cancelOpen loops).
     * Never use this while Android already holds the device — cancelOpen drops that link
     * and makes inventory start only on some taps.
     */
    private fun softDisconnectForRetry() {
        suppressDisconnectNotify = true
        isConnecting = false
        isConnected = false
        try {
            reader?.stopInventory()
        } catch (_: Throwable) {
        }
        try {
            reader?.disconnect()
        } catch (_: Throwable) {
        }
        SystemClock.sleep(350)
        suppressDisconnectNotify = false
    }

    private fun waitForHandshake(address: String, timeoutMs: Long): Boolean {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs.coerceAtLeast(1000L)
        while (SystemClock.elapsedRealtime() < deadline) {
            if (isReallyConnected() && currentAddress.equals(address, ignoreCase = true)) {
                return true
            }
            val remaining = deadline - SystemClock.elapsedRealtime()
            if (remaining <= 0L) break
            val latch = connectLatch.get()
            if (latch != null) {
                try {
                    latch.await(remaining.coerceAtMost(400L), TimeUnit.MILLISECONDS)
                } catch (_: InterruptedException) {
                    break
                }
            } else {
                SystemClock.sleep(200L)
            }
        }
        return isReallyConnected() && currentAddress.equals(address, ignoreCase = true)
    }

    private fun acceptOsHeldLink(address: String) {
        currentAddress = address
        isConnected = true
        isConnecting = false
        connectStartedAtMs = 0L
        connectLatch.get()?.countDown()
        Log.i(TAG, "Using Android-held GATT for $address (sdk=${sdkStatus()})")
        onConnectionChange(true, "OS_CONNECTED")
    }

    /**
     * Chainway R6 often needs a short BLE discovery so the MAC is "seen" before connect.
     */
    private fun preScanForDevice(address: String, maxMs: Long = 3500L): Boolean {
        val target = address.trim()
        if (target.isEmpty()) return false
        init()
        val sdk = reader ?: return false
        stopBtDiscoveryQuietly()
        val found = AtomicBoolean(false)
        val latch = CountDownLatch(1)
        val callback = ScanBTCallback { device: BluetoothDevice?, _: Int, _: ByteArray? ->
            val addr = device?.address?.trim().orEmpty()
            if (addr.equals(target, ignoreCase = true)) {
                found.set(true)
                latch.countDown()
            }
        }
        return try {
            Log.i(TAG, "Pre-scan for $target")
            sdk.startScanBTDevices(callback)
            latch.await(maxMs, TimeUnit.MILLISECONDS)
            found.get().also {
                Log.i(TAG, "Pre-scan found=$it for $target")
            }
        } catch (e: Throwable) {
            Log.e(TAG, "Pre-scan failed", e)
            false
        } finally {
            try {
                sdk.stopScanBTDevices()
            } catch (_: Throwable) {
            }
            discoveryRunning.set(false)
            SystemClock.sleep(150)
        }
    }

    fun connect(address: String) {
        if (address.isBlank()) return
        try {
            if (isReallyConnected() && currentAddress.equals(address, ignoreCase = true)) {
                onConnectionChange(true, "ALREADY_CONNECTED")
                return
            }

            val status = sdkStatus()
            val elapsed = connectElapsedMs()
            val sameTarget = currentAddress.equals(address, ignoreCase = true)
            val osHeld = isOsBluetoothConnected(address)
            if (sameTarget && (isConnecting || status == ConnectionStatus.CONNECTING)) {
                // Missing timestamp used to look like Long.MAX_VALUE elapsed and
                // cancelOpen() killed a live Android Bluetooth link.
                if (osHeld || connectStartedAtMs <= 0L || elapsed < CONNECT_GUARD_MS) {
                    markConnecting()
                    Log.i(TAG, "Connect already in progress for $address — skip cancelOpen")
                    return
                }
                clearStuckConnecting("stale in-progress connect (status=$status elapsed=${elapsed}ms)")
                if (!osHeld) {
                    softDisconnectForRetry()
                }
            }

            stopBtDiscoveryQuietly()
            init()

            val switching =
                currentAddress.isNotEmpty() && !currentAddress.equals(address, ignoreCase = true)
            if (switching && !osHeld) {
                Log.i(TAG, "Switching BLE target $currentAddress -> $address")
                softDisconnectForRetry()
            }

            currentAddress = address
            markConnecting()
            isConnected = false
            Log.i(TAG, "Connecting to $address")
            reader?.connect(address, btStatus)
        } catch (e: Throwable) {
            Log.e(TAG, "connect failed", e)
            isConnecting = false
            isConnected = false
            connectStartedAtMs = 0L
            onConnectionChange(false, e.message)
        }
    }

    private val connectLock = Any()

    private fun isOsBluetoothConnected(address: String): Boolean {
        val target = address.trim()
        if (target.isEmpty()) return false
        return try {
            @Suppress("DEPRECATION")
            val adapter = BluetoothAdapter.getDefaultAdapter() ?: return false
            for (device in adapter.bondedDevices.orEmpty()) {
                if (!device.address.equals(target, ignoreCase = true)) continue
                val method = device.javaClass.getMethod("isConnected")
                return method.invoke(device) as? Boolean ?: false
            }
            false
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Blocking connect (background thread only).
     * If Android already holds the tray/R6, wait for GATT — never cancelOpen.
     */
    fun connectAndWait(address: String, timeoutMs: Long = 20000L): Boolean {
        if (address.isBlank()) return false
        if (isReallyConnected() && currentAddress.equals(address, ignoreCase = true)) {
            return true
        }
        synchronized(connectLock) {
            if (isReallyConnected() && currentAddress.equals(address, ignoreCase = true)) {
                return true
            }

            val osConnected = isOsBluetoothConnected(address)
            val osWaitMs = if (osConnected) timeoutMs.coerceAtMost(8_000L) else timeoutMs
            val status = sdkStatus()
            val sameTarget = currentAddress.equals(address, ignoreCase = true) ||
                currentAddress.isEmpty()
            val inFlight = (isConnecting || status == ConnectionStatus.CONNECTING) &&
                (sameTarget || currentAddress.isEmpty())

            if (inFlight || (osConnected && status == ConnectionStatus.CONNECTING)) {
                stopBtDiscoveryQuietly()
                init()
                if (currentAddress.isEmpty()) currentAddress = address
                markConnecting()
                Log.i(
                    TAG,
                    "connectAndWait waiting for in-flight GATT $address os=$osConnected status=$status",
                )
                if (waitForHandshake(address, osWaitMs)) return true
                if (osConnected || isOsBluetoothConnected(address)) {
                    acceptOsHeldLink(address)
                    return true
                }
            }

            if (status == ConnectionStatus.CONNECTED) {
                currentAddress = address
                isConnected = true
                isConnecting = false
                return true
            }

            if (osConnected) {
                stopBtDiscoveryQuietly()
                init()
                currentAddress = address
                if (sdkStatus() != ConnectionStatus.CONNECTING && !isReallyConnected()) {
                    val latch = CountDownLatch(1)
                    connectLatch.set(latch)
                    markConnecting()
                    Log.i(TAG, "Connecting to OS-held $address")
                    try {
                        reader?.connect(address, btStatus)
                    } catch (e: Throwable) {
                        Log.e(TAG, "connect failed", e)
                    }
                } else {
                    markConnecting()
                }
                if (waitForHandshake(address, osWaitMs)) return true
                if (isOsBluetoothConnected(address)) {
                    acceptOsHeldLink(address)
                    return true
                }
                Log.w(TAG, "connectAndWait OS-held $address failed status=${sdkStatus()}")
                return false
            }

            if (!isReallyConnected()) {
                preScanForDevice(address, 3500L)
            }
            for (attempt in 1..2) {
                if (isReallyConnected() && currentAddress.equals(address, ignoreCase = true)) {
                    return true
                }
                if (isOsBluetoothConnected(address)) {
                    acceptOsHeldLink(address)
                    return true
                }

                val latch = CountDownLatch(1)
                connectLatch.set(latch)
                connect(address)

                val slice = if (attempt == 1) {
                    (timeoutMs * 2 / 3).coerceAtLeast(10_000L)
                } else {
                    (timeoutMs / 3).coerceAtLeast(8_000L)
                }
                val ok = try {
                    latch.await(slice, TimeUnit.MILLISECONDS) && isReallyConnected()
                } catch (_: InterruptedException) {
                    false
                }
                Log.i(TAG, "connectAndWait($address) attempt=$attempt => $ok status=${sdkStatus()}")
                connectLatch.compareAndSet(latch, null)
                if (ok || isReallyConnected()) return true
                if (isOsBluetoothConnected(address)) {
                    acceptOsHeldLink(address)
                    return true
                }

                if (attempt < 2) {
                    clearStuckConnecting("attempt $attempt timed out")
                    softDisconnectForRetry()
                }
            }
            return isReallyConnected()
        }
    }

    fun isOsLinked(address: String): Boolean = isOsBluetoothConnected(address)

    fun disconnect() {
        stopBtDiscoveryQuietly()
        isConnecting = false
        connectStartedAtMs = 0L
        suppressDisconnectNotify = false
        try {
            reader?.stopInventory()
            reader?.disconnect()
        } catch (_: Throwable) {
        }
        isConnected = false
        currentAddress = ""
    }

    fun scanNearbyDevices(durationMs: Int): List<Map<String, String>> {
        if (isConnecting || isReallyConnected()) {
            // Prefer bonded merge only while linked — avoid killing an active GATT.
            val found = Collections.synchronizedMap(LinkedHashMap<String, String>())
            mergeBondedDevices(found)
            return found.map { (address, name) ->
                mapOf("name" to name, "address" to address)
            }.sortedBy { it["name"]?.lowercase() }
        }
        if (!discoveryRunning.compareAndSet(false, true)) {
            return emptyList()
        }
        return try {
            init()
            val sdk = reader ?: return emptyList()
            try {
                sdk.stopScanBTDevices()
            } catch (_: Throwable) {
            }
            val found = Collections.synchronizedMap(LinkedHashMap<String, String>())
            val callback = ScanBTCallback { device: BluetoothDevice?, _: Int, _: ByteArray? ->
                if (device == null) return@ScanBTCallback
                val address = device.address?.trim().orEmpty()
                if (address.isEmpty()) return@ScanBTCallback
                val name = device.name?.trim()?.takeIf { it.isNotEmpty() } ?: "Bluetooth Device"
                found[address] = name
            }
            try {
                sdk.startScanBTDevices(callback)
            } catch (e: Throwable) {
                Log.e(TAG, "startScanBTDevices failed", e)
            }
            try {
                Thread.sleep(durationMs.coerceIn(2500, 8000).toLong())
            } catch (_: InterruptedException) {
            }
            try {
                sdk.stopScanBTDevices()
            } catch (_: Throwable) {
            }
            mergeBondedDevices(found)
            found.map { (address, name) ->
                mapOf("name" to name, "address" to address)
            }.sortedBy { it["name"]?.lowercase() }
        } catch (e: Throwable) {
            Log.e(TAG, "scanNearbyDevices failed", e)
            emptyList()
        } finally {
            stopBtDiscoveryQuietly()
        }
    }

    private fun mergeBondedDevices(found: MutableMap<String, String>) {
        try {
            @Suppress("DEPRECATION")
            val adapter = BluetoothAdapter.getDefaultAdapter() ?: return
            if (!adapter.isEnabled) return
            for (device in adapter.bondedDevices.orEmpty()) {
                val address = device.address?.trim().orEmpty()
                if (address.isEmpty()) continue
                val name = device.name?.trim()?.takeIf { it.isNotEmpty() } ?: "Bluetooth Device"
                if (found[address].isNullOrBlank()) {
                    found[address] = name
                }
            }
        } catch (_: Throwable) {
        }
    }

    fun setPower(power: Int): Boolean {
        return try {
            reader?.setPower(power) ?: false
        } catch (_: Throwable) {
            false
        }
    }

    fun triggerBeep(durationMs: Int = 40) {
        try {
            reader?.triggerBeep(durationMs)
        } catch (_: Throwable) {
        }
    }

    fun startInventory(): Boolean {
        return try {
            drainBuffer()
            val ok = reader?.startInventoryTag() ?: false
            Log.i(TAG, "startInventoryTag => $ok connected=$isConnected sdk=${sdkStatus()}")
            ok
        } catch (e: Throwable) {
            Log.e(TAG, "startInventory failed", e)
            false
        }
    }

    fun isReallyConnected(): Boolean {
        return try {
            when (sdkStatus()) {
                ConnectionStatus.CONNECTED -> {
                    isConnected = true
                    isConnecting = false
                    connectStartedAtMs = 0L
                    true
                }
                ConnectionStatus.CONNECTING -> {
                    markConnecting()
                    // Chainway often stays CONNECTING while Android already holds GATT.
                    isConnected &&
                        currentAddress.isNotEmpty() &&
                        isOsBluetoothConnected(currentAddress)
                }
                ConnectionStatus.DISCONNECTED -> {
                    isConnected = false
                    false
                }
                else -> isConnected
            }
        } catch (_: Throwable) {
            isConnected
        }
    }

    fun stopInventory(): Boolean {
        return try {
            reader?.stopInventory() ?: false
        } catch (_: Throwable) {
            false
        }
    }

    fun readTagFromBuffer(): UHFTAGInfo? {
        return try {
            reader?.readTagFromBuffer()
        } catch (_: Throwable) {
            null
        }
    }

    fun drainBuffer() {
        var drained = 0
        while (drained < 64) {
            val tag = readTagFromBuffer() ?: break
            if (tag.epc.isNullOrBlank()) break
            drained++
        }
    }
}
