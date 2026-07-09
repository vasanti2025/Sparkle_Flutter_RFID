package com.loyalstring.rfid.rfid_flutter

import android.content.Context
import com.rscja.deviceapi.RFIDWithUHFBLE
import com.rscja.deviceapi.entity.UHFTAGInfo
import com.rscja.deviceapi.interfaces.ConnectionStatus
import com.rscja.deviceapi.interfaces.ConnectionStatusCallback
import com.rscja.deviceapi.interfaces.IUHFInventoryCallback

class TrayReaderManager(
    private val context: Context,
    private val onTagRead: (epc: String, rssi: String) -> Unit,
    private val onConnectionChange: (connected: Boolean, message: String?) -> Unit,
) {
    private var reader: RFIDWithUHFBLE? = null

    @Volatile
    var isConnected: Boolean = false
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
            reader?.init(context) ?: false
        } catch (e: Throwable) {
            e.printStackTrace()
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

    fun connect(address: String) {
        if (address.isBlank()) return
        try {
            init()
            val callback = object : ConnectionStatusCallback<Any> {
                override fun getStatus(status: ConnectionStatus?, device: Any?) {
                    val connected = status == ConnectionStatus.CONNECTED
                    isConnected = connected
                    onConnectionChange(connected, status?.name)
                }
            }
            reader?.setConnectionStatusCallback(callback)
            reader?.connect(address, callback)
        } catch (e: Throwable) {
            e.printStackTrace()
            isConnected = false
            onConnectionChange(false, e.message)
        }
    }

    fun disconnect() {
        try {
            reader?.stopInventory()
            reader?.disconnect()
        } catch (_: Throwable) {
        }
        isConnected = false
    }

    fun setPower(power: Int): Boolean {
        return try {
            reader?.setPower(power) ?: false
        } catch (_: Throwable) {
            false
        }
    }

    fun startInventory(): Boolean {
        return try {
            drainBuffer()
            reader?.startInventoryTag() ?: false
        } catch (e: Throwable) {
            e.printStackTrace()
            false
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
