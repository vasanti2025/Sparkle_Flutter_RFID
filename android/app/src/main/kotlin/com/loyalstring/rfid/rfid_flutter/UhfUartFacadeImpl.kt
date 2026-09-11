package com.loyalstring.rfid.rfid_flutter

import android.content.Context

/** No Chainway imports — safe for MainActivity class loading. */
interface UhfFacade {
    fun initHardware(): Boolean
    fun setPower(power: Int): Boolean
    /** setPower + Chainway inventory defaults (focus/fastID/dynamicDistance). */
    fun prepareScan(power: Int): Boolean
    /**
     * uhf-uart-demo Tag LED Inventory start: power, optional EPC filter, mode 15.
     * Does not call setEPCMode — that turns LED blink off.
     */
    fun prepareSearchLed(power: Int, epcs: Collection<String>): Boolean
    fun startInventory(): Boolean
    fun stopInventory(): Boolean
    /** Demo Tag LED / Read Tag: tags arrive on this callback (no readTagFromBuffer poll). */
    fun setInventoryCallback(onTag: ((epc: String, rssi: String) -> Unit)?)
    /** @return epc to rssi, or null if buffer empty */
    fun readTagFromBuffer(): Pair<String, String>?
    fun isReady(): Boolean
    fun recoverHardware(): Boolean
    /**
     * Demo Tag LED Inventory "Blink": setFilter(matched EPCs) then mode 15.
     * Only those EPCs blink. Empty [epcs] returns false (do not blink all tags).
     */
    fun applyLedTagBlinkMode(epcs: Collection<String>): Boolean
    /**
     * Search LED inventory with no EPC filter so every chip stays readable
     * and LED tags blink as they are inventoried. Do not call setEPCMode after.
     */
    fun applyLedBlinkInventoryNoFilter(): Boolean
    /** Restore EPC-only inventory after Search (same as demo leaving Tag LED tab). */
    fun restoreEpcInventoryMode(): Boolean
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

    override fun recoverHardware(): Boolean {
        ready = false
        try {
            reader?.stopInventory()
        } catch (_: Throwable) {
        }
        try {
            val free = reader?.javaClass?.methods?.firstOrNull {
                it.name == "free" && it.parameterTypes.isEmpty()
            }
            free?.invoke(reader)
        } catch (_: Throwable) {
        }
        reader = null
        return initHardware()
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
            applyLedBlinkInventoryNoFilter()
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
                    val epc = try {
                        info.epc?.trim().orEmpty()
                    } catch (_: Throwable) {
                        ""
                    }.ifEmpty {
                        try {
                            info.getEPC()?.trim().orEmpty()
                        } catch (_: Throwable) {
                            ""
                        }
                    }
                    if (epc.isEmpty()) return
                    val rssi = try {
                        info.rssi?.toString() ?: "0"
                    } catch (_: Throwable) {
                        "0"
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
            val epc = tag.epc?.trim().orEmpty()
            if (epc.isEmpty()) return null
            val rssi = tag.rssi?.toString() ?: "0"
            epc to rssi
        } catch (_: Throwable) {
            null
        }
    }

    override fun applyLedBlinkInventoryNoFilter(): Boolean {
        return try {
            val r = reader ?: return false
            // Demo Tag LED / Settings "LED Tag": MODE_LED_TAG with no EPC filter.
            // Do not call setEPCMode first — that clears Select LED Tag mode.
            clearEpcFilters(r)
            val ledTag = com.rscja.deviceapi.entity.InventoryModeEntity.Builder()
                .setMode(com.rscja.deviceapi.entity.InventoryModeEntity.MODE_LED_TAG)
                .build()
            if (r.setEPCAndTIDUserMode(ledTag)) {
                android.util.Log.i("UhfUartFacade", "Select LED Tag mode (MODE_LED_TAG) no-filter")
                return true
            }
            val blink = com.rscja.deviceapi.entity.InventoryModeEntity.Builder()
                .setMode(15)
                .build()
            val ok = r.setEPCAndTIDUserMode(blink)
            android.util.Log.i("UhfUartFacade", "Search LED mode15 no-filter => $ok")
            ok
        } catch (e: Throwable) {
            android.util.Log.w("UhfUartFacade", "applyLedBlinkInventoryNoFilter failed: ${e.message}")
            false
        }
    }

    override fun applyLedTagBlinkMode(epcs: Collection<String>): Boolean {
        return try {
            val r = reader ?: return false
            val unique = ledEpcsOf(epcs)
            // Demo Tag LED: setFilter(checked EPCs) then LED mode.
            // Never unfiltered LED inventory — that lights every LED tag in range.
            if (unique.isEmpty()) return false
            val selected = if (unique.size <= 8) ArrayList(unique) else ArrayList(unique.take(8))
            if (!installEpcFilter(r, selected)) {
                android.util.Log.w("UhfUartFacade", "Search LED setFilter(${selected.size}) failed")
                return false
            }
            // uhf-uart-demo checkbox "LED tag" = MODE_LED_TAG (solid).
            val solid = com.rscja.deviceapi.entity.InventoryModeEntity.Builder()
                .setMode(com.rscja.deviceapi.entity.InventoryModeEntity.MODE_LED_TAG)
                .build()
            if (r.setEPCAndTIDUserMode(solid)) {
                android.util.Log.i("UhfUartFacade", "Search LED MODE_LED_TAG epcs=${selected.size}")
                return true
            }
            // Demo checkbox "blink" = mode 15.
            val blink = com.rscja.deviceapi.entity.InventoryModeEntity.Builder()
                .setMode(15)
                .build()
            val ok = r.setEPCAndTIDUserMode(blink)
            android.util.Log.i("UhfUartFacade", "Search LED mode15 fallback epcs=${selected.size} => $ok")
            ok
        } catch (e: Throwable) {
            android.util.Log.w("UhfUartFacade", "applyLedTagBlinkMode failed: ${e.message}")
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
            val epc = raw.trim()
            if (epc.isNotEmpty()) unique.add(epc)
        }
        return unique
    }

    /** Demo uses whatever getEPC() returns; do not require 24/32 only. */
    private fun isLedEpcHex(epc: String): Boolean {
        if (epc.length < 4 || epc.length > 128 || epc.length % 2 != 0) return false
        return epc.all { ch -> ch in '0'..'9' || ch in 'A'..'F' }
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
        if (selected.size == 1) {
            val epc = selected[0]
            return try {
                r.setFilter(
                    com.rscja.deviceapi.interfaces.IUHF.Bank_EPC,
                    32,
                    epc.length * 4,
                    epc,
                ) || r.setFilter(
                    com.rscja.deviceapi.interfaces.IUHF.Bank_EPC,
                    0,
                    epc.length * 4,
                    epc,
                )
            } catch (_: Throwable) {
                false
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
