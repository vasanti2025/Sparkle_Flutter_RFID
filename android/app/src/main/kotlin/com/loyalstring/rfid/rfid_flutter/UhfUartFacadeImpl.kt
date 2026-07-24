package com.loyalstring.rfid.rfid_flutter

import android.content.Context

/** No Chainway imports — safe for MainActivity class loading. */
interface UhfFacade {
    fun initHardware(): Boolean
    fun setPower(power: Int): Boolean
    /** setPower + Chainway inventory defaults (focus/fastID/dynamicDistance). */
    fun prepareScan(power: Int): Boolean
    fun startInventory(): Boolean
    fun stopInventory(): Boolean
    /** @return epc to rssi, or null if buffer empty */
    fun readTagFromBuffer(): Pair<String, String>?
    fun isReady(): Boolean
}

/**
 * Loaded only via reflection so DeviceAPI native lib is NOT pulled in at process start.
 */
class UhfUartFacadeImpl(private val context: Context) : UhfFacade {
    private var reader: com.rscja.deviceapi.RFIDWithUHFUART? = null
    @Volatile private var ready = false

    override fun isReady(): Boolean = ready && reader != null

    override fun initHardware(): Boolean {
        if (ready && reader != null) return true
        return try {
            if (reader == null) {
                reader = com.rscja.deviceapi.RFIDWithUHFUART.getInstance()
            }
            val ok = reader?.init(context) ?: false
            ready = ok
            ok
        } catch (e: Throwable) {
            e.printStackTrace()
            false
        }
    }

    override fun setPower(power: Int): Boolean {
        return try {
            reader?.setPower(power) ?: false
        } catch (_: Throwable) {
            false
        }
    }

    override fun prepareScan(power: Int): Boolean {
        return try {
            val r = reader ?: return false
            r.setPower(power)
            r.setTagFocus(false)
            r.setFastID(false)
            r.setDynamicDistance(0)
            true
        } catch (_: Throwable) {
            false
        }
    }

    override fun startInventory(): Boolean {
        return try {
            reader?.startInventoryTag() ?: false
        } catch (_: Throwable) {
            false
        }
    }

    override fun stopInventory(): Boolean {
        return try {
            reader?.stopInventory() ?: false
        } catch (_: Throwable) {
            false
        }
    }

    override fun readTagFromBuffer(): Pair<String, String>? {
        return try {
            val tag = reader?.readTagFromBuffer() ?: return null
            val epc = tag.epc?.trim().orEmpty()
            if (epc.isEmpty()) return null
            val rssi = tag.rssi?.toString() ?: "0"
            epc to rssi
        } catch (_: Throwable) {
            null
        }
    }
}
