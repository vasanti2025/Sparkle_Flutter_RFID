package com.loyalstring.rfid.rfid_flutter

import android.content.Context

/** No Chainway imports — safe for MainActivity class loading. */
interface UhfFacade {
    fun initHardware(): Boolean
    fun setPower(power: Int): Boolean
    /** setPower + Chainway inventory defaults (focus/fastID/dynamicDistance). */
    fun prepareScan(power: Int): Boolean
    /** Scan Display inventory: power only. Does not change Search LED mode or filters. */
    fun prepareInventory(power: Int): Boolean
    /**
     * Search: uhf-uart-demo Tag LED Inventory with Solid.
     * Non-empty [epcs] = checked rows (only those light). Empty = first pass (LED+normal scan).
     */
    fun prepareSearchLed(power: Int, epcs: Collection<String>): Boolean
    fun startInventory(): Boolean
    fun stopInventory(): Boolean
    /** Demo Tag LED / Read Tag: tags arrive on this callback (no readTagFromBuffer poll). */
    fun setInventoryCallback(onTag: ((epc: String, rssi: String) -> Unit)?)
    /** @return epc to rssi, or null if buffer empty */
    fun readTagFromBuffer(): Pair<String, String>?
    fun isReady(): Boolean
    /** True while the SDK is already running an inventory. startInventoryTag returns false in that case. */
    fun isInventorying(): Boolean
    /** Java power flag. False after the SDK frees the module (background / other app). */
    fun modulePowered(): Boolean
    fun recoverHardware(): Boolean
    /**
     * startInventory failed while this process still thinks the UART is open.
     * One SDK free(), then a real init(). Not used when init() itself failed.
     */
    fun reopenStalePort(): Boolean
    /** Process is leaving. free() only if this process powered the module. */
    fun closeQuietly()
    /**
     * Demo Tag LED "Solid" + checked EPCs: setFilter then MODE_LED_TAG (14).
     * Empty [epcs] returns false — use [applyLedBlinkInventoryNoFilter] for the first pass.
     */
    fun applyLedTagBlinkMode(epcs: Collection<String>): Boolean
    /** Re-assert Select LED Tag solid (mode 14). Does not change the EPC filter. */
    fun applyLedTagSolidMode(): Boolean
    /**
     * startInventoryTag can clear user mode. If solid (14) dropped, stop, set it
     * again, and start. No-op when mode 14 is already active.
     */
    fun reassertLedSolidIfCleared(): Boolean
    /**
     * Demo Tag LED first pass: setFilter(empty list) + Solid (MODE_LED_TAG).
     * LED tags and normal tags both inventory. Lock to searched EPCs after a hit.
     */
    fun applyLedBlinkInventoryNoFilter(): Boolean
    /**
     * Inventory is already stopped. EPC mode and an empty filter so a list
     * scan can see every tag in range. Does not light LEDs.
     */
    fun beginEpcSniff(): Boolean
    /** Restore EPC-only inventory after Search (same as demo leaving Tag LED tab). */
    fun restoreEpcInventoryMode(): Boolean
}

/**
 * Loaded only via reflection so DeviceAPI native lib is NOT pulled in at process start.
 */
class UhfUartFacadeImpl(private val context: Context) : UhfFacade {
    /**
     * DeviceAPI 2.0.3 command 0x70 keeps MODE_LED_TAG (14).
     * reservedOffset = on time, reservedLength = off time, unit 100ms.
     * 0 and 0 stays solid for every tag in the filter. Mode 15 is temperature
     * and turns the tag LED off — do not use it.
     */
    private val ledBlinkOn = 0
    private val ledBlinkOff = 0
    private var reader: com.rscja.deviceapi.RFIDWithUHFUART? = null
    @Volatile private var ready = false

    override fun isReady(): Boolean = ready && reader != null

    override fun initHardware(): Boolean {
        // API 36 init() runs UHFVerify before it checks power. A second init
        // on a live module returns "no permission" and the next scan never starts.
        // If the SDK freed the module (screen off, other app, process resume),
        // power is off and we must open again.
        if (reader != null && moduleIsOn()) {
            ready = true
            return true
        }
        ready = false
        return try {
            if (reader == null) {
                reader = com.rscja.deviceapi.RFIDWithUHFUART.getInstance()
            }
            clearStuckWorkingFlag(reader)
            val opened = try {
                reader?.init(context) == true
            } catch (_: Throwable) {
                false
            }
            // A failed UHFVerify can leave isPowerOn true. Do not free() that
            // module — free() then makes the next init fail for good.
            val ok = opened || moduleIsOn()
            ready = ok
            if (!ok) {
                android.util.Log.e("UhfUartFacade", "reader init failed")
            }
            ok
        } catch (e: Throwable) {
            e.printStackTrace()
            ready = false
            false
        }
    }

    private fun openReader(): Boolean {
        if (reader == null) {
            reader = com.rscja.deviceapi.RFIDWithUHFUART.getInstance()
        }
        val r = reader ?: return false
        // Always ask the SDK to open. If Android 16 rejects init while the
        // module is already powered, that module is still usable.
        val opened = try {
            r.init(context)
        } catch (_: Throwable) {
            false
        }
        if (opened) return true
        return moduleIsOn()
    }

    /** True only after the SDK has powered the UART module. A power reading alone is not enough. */
    private fun moduleIsOn(): Boolean {
        val r = reader ?: return false
        return try {
            r.isPowerOn
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * stopInventory() returns without clearing isWorking when power is already
     * off, so every later startInventoryTag logs "already start!" and returns
     * false. The flag is private. Clear it only in that stuck state.
     */
    private fun clearStuckWorkingFlag(r: com.rscja.deviceapi.RFIDWithUHFUART?) {
        val reader = r ?: return
        val powered = try {
            reader.isPowerOn
        } catch (_: Throwable) {
            false
        }
        val working = try {
            reader.isInventorying
        } catch (_: Throwable) {
            false
        }
        if (powered || !working) return
        try {
            val field = reader.javaClass.getDeclaredField("isWorking")
            field.isAccessible = true
            field.setBoolean(reader, false)
            android.util.Log.i("UhfUartFacade", "cleared stuck isWorking")
        } catch (e: Throwable) {
            android.util.Log.w("UhfUartFacade", "clear isWorking failed: ${e.message}")
        }
    }

    private fun releaseReader() {
        ready = false
        val r = reader ?: return
        try {
            r.stopInventory()
        } catch (_: Throwable) {
        }
        val powered = try {
            r.isPowerOn
        } catch (_: Throwable) {
            false
        }
        if (powered) {
            // Process is leaving. UHFFree releases the daemon port so the
            // next launch can UHFInit. Do not Module.powerOff.
            try {
                r.free()
            } catch (_: Throwable) {
            }
        } else {
            clearStuckWorkingFlag(r)
        }
        reader = null
    }

    override fun isInventorying(): Boolean {
        val r = reader ?: return false
        return try {
            r.isInventorying
        } catch (_: Throwable) {
            false
        }
    }

    override fun modulePowered(): Boolean = moduleIsOn()

    override fun recoverHardware(): Boolean {
        // Never free() here. init() failed, and free() on a powered module
        // makes the next open return "no permission".
        val r = reader ?: return initHardware()
        try {
            r.stopInventory()
        } catch (_: Throwable) {
        }
        try {
            Thread.sleep(80L)
        } catch (_: InterruptedException) {
        }
        if (moduleIsOn()) {
            ready = true
            return true
        }
        clearStuckWorkingFlag(r)
        ready = false
        return initHardware()
    }

    override fun reopenStalePort(): Boolean {
        val r = reader ?: return initHardware()
        try {
            r.stopInventory()
        } catch (_: Throwable) {
        }
        try {
            Thread.sleep(80L)
        } catch (_: InterruptedException) {
        }
        if (!moduleIsOn()) {
            clearStuckWorkingFlag(r)
            ready = false
            return initHardware()
        }
        android.util.Log.w("UhfUartFacade", "reopen stale UART")
        try {
            r.free()
        } catch (_: Throwable) {
        }
        ready = false
        return initHardware()
    }

    override fun closeQuietly() {
        releaseReader()
    }

    override fun setPower(power: Int): Boolean {
        return try {
            reader?.setPower(power) ?: false
        } catch (_: Throwable) {
            false
        }
    }

    override fun prepareInventory(power: Int): Boolean {
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

    override fun prepareScan(power: Int): Boolean {
        return try {
            val r = reader ?: return false
            r.setPower(power)
            r.setTagFocus(false)
            r.setFastID(false)
            r.setDynamicDistance(0)
            // Pushpa Searchfragment / Inventoryfragment: EPC-only inventory.
            try {
                r.setEPCMode()
            } catch (_: Throwable) {
            }
            clearEpcFilters(r)
            true
        } catch (_: Throwable) {
            false
        }
    }

    override fun prepareSearchLed(power: Int, epcs: Collection<String>): Boolean {
        return try {
            val r = reader ?: return false
            r.setPower(power)
            r.setTagFocus(false)
            r.setFastID(false)
            r.setDynamicDistance(0)
            if (epcs.any { it.isNotBlank() }) {
                applyLedTagBlinkMode(epcs)
            } else {
                applyLedBlinkInventoryNoFilter()
            }
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

    override fun setInventoryCallback(onTag: ((epc: String, rssi: String) -> Unit)?) {
        try {
            val r = reader ?: return
            if (onTag == null) {
                r.setInventoryCallback(null)
                return
            }
            r.setInventoryCallback(object : com.rscja.deviceapi.interfaces.IUHFInventoryCallback {
                override fun callback(info: com.rscja.deviceapi.entity.UHFTAGInfo) {
                    // Demo Tag LED uses getEPC() — info.epc can be EPC+TID+USER in LED mode.
                    val epc = try {
                        info.getEPC()?.trim().orEmpty()
                    } catch (_: Throwable) {
                        ""
                    }.ifEmpty {
                        try {
                            info.epc?.trim().orEmpty()
                        } catch (_: Throwable) {
                            ""
                        }
                    }
                    if (epc.isEmpty()) return
                    val rssi = try {
                        info.rssi?.toString()?.trim().orEmpty()
                    } catch (_: Throwable) {
                        ""
                    }.ifEmpty {
                        try {
                            info.getRssi()?.trim().orEmpty()
                        } catch (_: Throwable) {
                            ""
                        }
                    }
                    onTag(epc, rssi)
                }
            })
        } catch (e: Throwable) {
            android.util.Log.w("UhfUartFacade", "setInventoryCallback failed: ${e.message}")
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
            val epc = try {
                tag.getEPC()?.trim().orEmpty()
            } catch (_: Throwable) {
                ""
            }.ifEmpty {
                tag.epc?.trim().orEmpty()
            }
            if (epc.isEmpty()) return null
            val rssi = try {
                tag.rssi?.toString()?.trim().orEmpty()
            } catch (_: Throwable) {
                ""
            }.ifEmpty {
                try {
                    tag.getRssi()?.trim().orEmpty()
                } catch (_: Throwable) {
                    ""
                }
            }
            epc to rssi
        } catch (_: Throwable) {
            null
        }
    }

    override fun applyLedBlinkInventoryNoFilter(): Boolean {
        return try {
            val r = reader ?: return false
            // uhf-uart-demo Tag LED start with no rows checked:
            // setFilter(empty list) then Solid = MODE_LED_TAG.
            val emptied = try {
                r.setFilter(ArrayList<com.rscja.deviceapi.entity.FilterEntity>())
            } catch (_: Throwable) {
                false
            }
            if (!emptied) {
                try {
                    r.setFilter(0, 0, 0, "")
                } catch (_: Throwable) {
                    clearEpcFilters(r)
                }
            }
            val ok = setLedTagSolid(r)
            android.util.Log.i("UhfUartFacade", "Tag LED Inventory Solid (no check) => $ok")
            ok
        } catch (e: Throwable) {
            android.util.Log.w("UhfUartFacade", "Tag LED first pass failed: ${e.message}")
            false
        }
    }

    override fun applyLedTagBlinkMode(epcs: Collection<String>): Boolean {
        return try {
            val r = reader ?: return false
            val unique = ledEpcsOf(epcs)
            if (unique.isEmpty()) return false
            val filterEpcs = ArrayList(unique)
            if (filterEpcs.size > 8) {
                while (filterEpcs.size > 8) filterEpcs.removeAt(filterEpcs.size - 1)
            }
            // setFilter / setEPCAndTIDUserMode are ignored while inventory is running.
            stopInventoryQuiet(r)
            try {
                r.setFilter(ArrayList<com.rscja.deviceapi.entity.FilterEntity>())
            } catch (_: Throwable) {
                clearEpcFilters(r)
            }
            // Demo Tag LED checked rows: offset 32 only. Offset 0 lights other chips.
            if (!installEpcFilterStrict(r, filterEpcs)) {
                android.util.Log.w("UhfUartFacade", "Search LED strict setFilter(${filterEpcs.size}) failed")
                return false
            }
            val ok = setLedTagSolid(r)
            android.util.Log.i("UhfUartFacade", "Search LED Tag MODE_LED_TAG epcs=${filterEpcs.size} => $ok")
            ok
        } catch (e: Throwable) {
            android.util.Log.w("UhfUartFacade", "applyLedTagBlinkMode failed: ${e.message}")
            false
        }
    }

    override fun reassertLedSolidIfCleared(): Boolean {
        return try {
            val r = reader ?: return false
            val current = try {
                r.getEPCAndTIDUserMode()
            } catch (_: Throwable) {
                null
            }
            if (current != null &&
                current.getMode() == com.rscja.deviceapi.entity.InventoryModeEntity.MODE_LED_TAG &&
                current.getReservedOffset() == ledBlinkOn &&
                current.getReservedLength() == ledBlinkOff
            ) {
                return true
            }
            android.util.Log.w("UhfUartFacade", "LED left solid — reapplying on=$ledBlinkOn off=$ledBlinkOff")
            stopInventoryQuiet(r)
            if (!setLedTagSolid(r)) return false
            r.startInventoryTag()
        } catch (e: Throwable) {
            android.util.Log.w("UhfUartFacade", "reassert LED solid failed: ${e.message}")
            false
        }
    }

    private fun stopInventoryQuiet(r: com.rscja.deviceapi.RFIDWithUHFUART) {
        try {
            r.stopInventory()
        } catch (_: Throwable) {
        }
        try {
            Thread.sleep(40L)
        } catch (_: InterruptedException) {
        }
    }

    override fun applyLedTagSolidMode(): Boolean {
        return try {
            val r = reader ?: return false
            setLedTagSolid(r)
        } catch (e: Throwable) {
            android.util.Log.w("UhfUartFacade", "applyLedTagSolidMode failed: ${e.message}")
            false
        }
    }

    /** Tag LED solid. Mode stays MODE_LED_TAG (14). 0,0 keeps every filtered tag on. */
    private fun setLedTagSolid(r: com.rscja.deviceapi.RFIDWithUHFUART): Boolean {
        val solid = com.rscja.deviceapi.entity.InventoryModeEntity.Builder()
            .setMode(com.rscja.deviceapi.entity.InventoryModeEntity.MODE_LED_TAG)
            .setReservedOffset(ledBlinkOn)
            .setReservedLength(ledBlinkOff)
            .build()
        val ok = r.setEPCAndTIDUserMode(solid)
        android.util.Log.i("UhfUartFacade", "LED solid MODE_LED_TAG 0,0 => $ok")
        return ok
    }

    override fun beginEpcSniff(): Boolean {
        val r = reader ?: return false
        return try {
            try {
                r.setEPCMode()
            } catch (_: Throwable) {
            }
            val emptied = try {
                r.setFilter(ArrayList<com.rscja.deviceapi.entity.FilterEntity>())
            } catch (_: Throwable) {
                false
            }
            if (!emptied) clearEpcFilters(r)
            true
        } catch (_: Throwable) {
            false
        }
    }

    override fun restoreEpcInventoryMode(): Boolean {
        return try {
            val r = reader ?: return false
            // uhf-uart-demo Tag LED onStop: setFilter(0, 0, 0, "") then leave LED mode.
            try {
                r.setFilter(0, 0, 0, "")
            } catch (_: Throwable) {
                clearEpcFilters(r)
            }
            r.setEPCMode()
        } catch (_: Throwable) {
            false
        }
    }

    private fun ledEpcsOf(epcs: Collection<String>): LinkedHashSet<String> {
        val unique = LinkedHashSet<String>()
        for (raw in epcs) {
            val epc = raw.trim().uppercase()
            // Item-code tags (SP24 → 53503234) are shorter than 24/32 and still
            // need Bank_EPC offset 32. Length is epc.length * 4 bits.
            val n = epc.length
            if (n < 8 || n > 64 || n % 2 != 0) continue
            if (epc.any { ch -> ch !in '0'..'9' && ch !in 'A'..'F' }) continue
            val chip = if (n > 32 && isChipHex(epc.substring(0, 32))) epc.substring(0, 32) else epc
            unique.add(chip)
        }
        return unique
    }

    private fun isChipHex(epc: String): Boolean {
        return (epc.length == 24 || epc.length == 32) &&
            epc.all { ch -> ch in '0'..'9' || ch in 'A'..'F' }
    }

    /**
     * Demo Tag LED checked filter only: Bank_EPC, offset 32, epc.length*4.
     * Offset 0 is not used — it can light a different chip.
     */
    private fun installEpcFilterStrict(
        r: com.rscja.deviceapi.RFIDWithUHFUART,
        selected: List<String>,
    ): Boolean {
        if (selected.isEmpty()) return false
        if (tryFilterList(r, selected, 32)) return true
        // A one-tag fallback would leave the 3rd list tag dark. Retry the full set.
        if (selected.size > 1) {
            clearEpcFilters(r)
            return tryFilterList(r, selected, 32)
        }
        for (epc in selected) {
            try {
                if (r.setFilter(
                        com.rscja.deviceapi.interfaces.IUHF.Bank_EPC,
                        32,
                        epc.length * 4,
                        epc,
                    )
                ) return true
            } catch (_: Throwable) {
            }
        }
        return false
    }

    /**
     * Demo Tag LED: FilterEntity(Bank_EPC, 32, epc.length*4, epc).
     * Fall back to offset 0 and single-EPC setFilter if the list API fails.
     */
    private fun installEpcFilter(
        r: com.rscja.deviceapi.RFIDWithUHFUART,
        selected: List<String>,
    ): Boolean {
        if (tryFilterList(r, selected, 32)) return true
        if (tryFilterList(r, selected, 0)) return true
        for (epc in selected) {
            val one = listOf(epc)
            if (tryFilterList(r, one, 32)) return true
            if (tryFilterList(r, one, 0)) return true
            try {
                if (r.setFilter(
                        com.rscja.deviceapi.interfaces.IUHF.Bank_EPC,
                        32,
                        epc.length * 4,
                        epc,
                    )
                ) return true
                if (r.setFilter(
                        com.rscja.deviceapi.interfaces.IUHF.Bank_EPC,
                        0,
                        epc.length * 4,
                        epc,
                    )
                ) return true
            } catch (_: Throwable) {
            }
        }
        return false
    }

    private fun tryFilterList(
        r: com.rscja.deviceapi.RFIDWithUHFUART,
        selected: List<String>,
        offset: Int,
    ): Boolean {
        return try {
            val filterList = ArrayList<com.rscja.deviceapi.entity.FilterEntity>(selected.size)
            for (epc in selected) {
                filterList.add(
                    com.rscja.deviceapi.entity.FilterEntity(
                        com.rscja.deviceapi.interfaces.IUHF.Bank_EPC,
                        offset,
                        epc.length * 4,
                        epc,
                    ),
                )
            }
            r.setFilter(filterList)
        } catch (_: Throwable) {
            false
        }
    }

    /** Demo leaving Tag LED tab: setFilter(0, 0, 0, ""). */
    private fun clearEpcFilters(r: com.rscja.deviceapi.RFIDWithUHFUART) {
        try {
            r.setFilter(com.rscja.deviceapi.interfaces.IUHF.Bank_EPC, 0, 0, "")
        } catch (_: Throwable) {
        }
        try {
            r.setFilter(com.rscja.deviceapi.interfaces.IUHF.Bank_TID, 0, 0, "")
        } catch (_: Throwable) {
        }
        try {
            r.setFilter(com.rscja.deviceapi.interfaces.IUHF.Bank_USER, 0, 0, "")
        } catch (_: Throwable) {
        }
    }

}
