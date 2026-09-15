package com.loyalstring.rfid.rfid_flutter

import android.content.Context

/** No Chainway imports — safe for MainActivity class loading. */
interface UhfFacade {
    fun initHardware(): Boolean
    fun setPower(power: Int): Boolean
    /** setPower + Chainway inventory defaults (focus/fastID/dynamicDistance). */
    fun prepareScan(power: Int): Boolean
    /**
     * Search: LabelStock EPCs as demo "checked" tags, then Blink (mode 15).
     * Empty [epcs] does not enable unfiltered LED (that lights every chip).
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
     * Demo Tag LED Inventory "Blink": setFilter(LabelStock EPCs) then mode 15.
     * Only those chips blink. Empty [epcs] returns false (do not light all tags).
     */
    fun applyLedTagBlinkMode(epcs: Collection<String>): Boolean
    /** Re-assert Select LED Tag solid (mode 14). Does not change the EPC filter. */
    fun applyLedTagSolidMode(): Boolean
    /**
     * Unfiltered LED Tag mode lights every LED in range. Search must never use it.
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
            if (epcs.any { it.isNotBlank() }) {
                applyLedTagBlinkMode(epcs)
            } else {
                r.setEPCMode()
                clearEpcFilters(r)
                true
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
        android.util.Log.w(
            "UhfUartFacade",
            "Unfiltered LED Tag mode refused (would light every LED in range)",
        )
        return false
    }

    override fun applyLedTagBlinkMode(epcs: Collection<String>): Boolean {
        return try {
            val r = reader ?: return false
            val unique = ledEpcsOf(epcs)
            if (unique.isEmpty()) return false
            val selected = ArrayList(unique)
            selected.sortWith(
                compareByDescending<String> {
                    if (it.length == 24) 2 else if (it.length == 32) 1 else 0
                }.thenByDescending { it.length },
            )
            val filterEpcs = if (selected.size <= 8) selected else ArrayList(selected.take(8))
            if (!installEpcFilter(r, filterEpcs)) {
                android.util.Log.w("UhfUartFacade", "Search LED setFilter(${filterEpcs.size}) failed")
                return false
            }
            // Demo checkbox "LED tag" = MODE_LED_TAG. Filter is already LabelStock-only.
            val ok = setLedTagSolid(r)
            android.util.Log.i("UhfUartFacade", "Search LED Tag MODE_LED_TAG epcs=${filterEpcs.size} => $ok")
            ok
        } catch (e: Throwable) {
            android.util.Log.w("UhfUartFacade", "applyLedTagBlinkMode failed: ${e.message}")
            false
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

    /** Demo "Solid" / Select LED Tag: MODE_LED_TAG = 14. */
    private fun setLedTagSolid(r: com.rscja.deviceapi.RFIDWithUHFUART): Boolean {
        val solid = com.rscja.deviceapi.entity.InventoryModeEntity.Builder()
            .setMode(com.rscja.deviceapi.entity.InventoryModeEntity.MODE_LED_TAG)
            .build()
        if (!r.setEPCAndTIDUserMode(solid)) return false
        try {
            val applied = r.getEPCAndTIDUserMode()?.getMode()
            if (applied != null && applied == 15) {
                android.util.Log.w("UhfUartFacade", "Reader stayed in blink mode 15 — forcing solid 14")
                return r.setEPCAndTIDUserMode(solid)
            }
        } catch (_: Throwable) {
        }
        return true
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
