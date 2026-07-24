package com.loyalstring.rfid.rfid_flutter

import android.content.Context
import android.util.Log
import net.posprinter.IConnectListener
import net.posprinter.IDeviceConnection
import net.posprinter.POSConnect
import net.posprinter.POSConst
import net.posprinter.POSPrinter
import java.text.SimpleDateFormat
import java.util.Locale

/**
 * Xprinter Bluetooth print — same layout as Sparkle PrinterManager.printDeliveryChallanCompact.
 */
class PrinterManager(private val context: Context) {

    private var deviceConnection: IDeviceConnection? = null
    private var posPrinter: POSPrinter? = null

    fun connectBluetooth(macAddress: String, onResult: (Boolean, String) -> Unit) {
        var replied = false
        fun replyOnce(ok: Boolean, msg: String) {
            if (replied) return
            replied = true
            onResult(ok, msg)
        }

        try {
            disconnect()
            Thread.sleep(300)
        } catch (_: Exception) {
        }

        try {
            deviceConnection = POSConnect.createDevice(POSConnect.DEVICE_TYPE_BLUETOOTH)
            if (deviceConnection == null) {
                replyOnce(false, "Unable to create Bluetooth printer connection")
                return
            }
            deviceConnection?.connect(macAddress, object : IConnectListener {
                override fun onStatus(code: Int, connectInfo: String?, message: String?) {
                    Log.d("PRINTER", "BT status=$code info=$connectInfo msg=$message")
                    if (code == POSConnect.CONNECT_SUCCESS) {
                        posPrinter = POSPrinter(deviceConnection)
                        replyOnce(true, message ?: "Bluetooth printer connected")
                    } else {
                        Log.d("PRINTER", "Waiting for CONNECT_SUCCESS (got $code)")
                    }
                }
            })
        } catch (e: Exception) {
            Log.e("PRINTER", "connectBluetooth error", e)
            replyOnce(false, e.message ?: "Bluetooth printer connection failed")
        }
    }

    fun disconnect() {
        try {
            deviceConnection?.close()
        } catch (e: Exception) {
            Log.e("PRINTER", "disconnect error", e)
        }
        deviceConnection = null
        posPrinter = null
    }

    fun isConnected(): Boolean = deviceConnection?.isConnect() == true

    /** Printable ASCII only — avoids '?' on thermal printers. */
    private fun safe(value: String?, fallback: String = ""): String {
        val raw = value?.trim().orEmpty()
        if (raw.isEmpty()) return fallback
        val cleaned = buildString(raw.length) {
            for (ch in raw) {
                append(if (ch.code in 32..126) ch else ' ')
            }
        }.trim().replace(Regex(" +"), " ")
        return cleaned.ifEmpty { fallback }
    }

    private fun cleanWeight(value: String?): String {
        val raw = value
            ?.replace("gm", "", ignoreCase = true)
            ?.replace("g", "", ignoreCase = true)
            ?.trim()
            .orEmpty()
        val number = raw.toDoubleOrNull() ?: 0.0
        return String.format(Locale.US, "%.3f", number)
    }

    private fun formatDate(value: String?): String {
        val raw = safe(value, "-")
        return try {
            val formats = listOf(
                SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()),
                SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()),
                SimpleDateFormat("dd-MM-yyyy", Locale.getDefault())
            )
            val parsed = formats.firstNotNullOfOrNull { fmt ->
                try {
                    fmt.parse(raw)
                } catch (_: Exception) {
                    null
                }
            }
            if (parsed != null) {
                SimpleDateFormat("dd-MM-yyyy", Locale.getDefault()).format(parsed)
            } else {
                raw
            }
        } catch (_: Exception) {
            raw
        }
    }

    private fun padRight(value: String, length: Int): String {
        val v = value.trim()
        return if (v.length >= length) v.take(length) else v + " ".repeat(length - v.length)
    }

    private fun padLeft(value: String, length: Int): String {
        val v = value.trim()
        return if (v.length >= length) v.take(length) else " ".repeat(length - v.length) + v
    }

    private fun fitItemName(value: String, length: Int): String {
        val clean = safe(value, "-")
        return if (clean.length > length) clean.take(length) else clean
    }

    /** Same visual width as table row (7+16+4+10+10 = 47). */
    private companion object {
        const val COL_WIDTH = 47
    }

    /**
     * One thin dark horizontal line, same width as the table text.
     *
     * Do NOT use ESC-star / GS-v-0 solid bars on this printer — they print as
     * thick blurred half-width blocks. Thick underline on spaces = sharp rule.
     */
    private fun hLine(printer: POSPrinter): POSPrinter {
        val cmd = byteArrayOf(
            0x1B, 0x21, 0x00, // ESC ! 0 — normal size (cancel 2x header)
            0x1B, 0x61, 0x00, // left align
            0x1B, 0x45, 0x01, // bold ON — darker stroke
            0x1B, 0x2D, 0x02, // ESC - 2 — thick underline ON
        ) + ByteArray(COL_WIDTH) { 0x20 } + byteArrayOf(
            0x0A,
            0x1B, 0x2D, 0x00, // underline OFF
            0x1B, 0x45, 0x00, // bold OFF
        )
        return printer.sendData(cmd)
    }

    private fun cleanAmount(value: String?): String {
        val raw = value?.replace(",", "")?.trim().orEmpty()
        val number = raw.toDoubleOrNull() ?: 0.0
        return String.format(Locale.US, "%.2f", number)
    }

    private fun totalAmountRow(amount: String): String {
        val label = "Total Amount:"
        val value = cleanAmount(amount)
        val lineWidth = COL_WIDTH
        val gap = (lineWidth - label.length - value.length).coerceAtLeast(1)
        return label + " ".repeat(gap) + value
    }

    private fun resolvePrintTotalAmount(
        data: DeliveryChallanPrintData,
        items: List<DeliveryChallanItemPrint>
    ): Double {
        return data.totalNetAmount.toDoubleOrNull()?.takeIf { it > 0.0 }
            ?: items.sumOf { cleanAmount(it.itemAmount).toDoubleOrNull() ?: 0.0 }
    }

    /**
     * Same as Sparkle Kotlin:
     * SNo(7) + Item(16) + PCS(4) + G.W(10) + N.W(10) = 47
     */
    private fun itemRow(
        sno: String,
        itemName: String,
        pcs: String,
        grossWt: String,
        netWt: String
    ): String {
        return buildString {
            append(padRight(safe(sno), 7))
            append(padRight(fitItemName(itemName, 16), 16))
            append(padLeft(safe(pcs), 4))
            append(padLeft(safe(grossWt), 10))
            append(padLeft(safe(netWt), 10))
        }
    }

    /** SNo(7) + Item(12) + G.W(8) + N.W(8) + St.Amt(8) */
    private fun itemRowWeightStone(
        sno: String,
        itemName: String,
        grossWt: String,
        netWt: String,
        stoneAmt: String
    ): String {
        return buildString {
            append(padRight(safe(sno), 7))
            append(padRight(fitItemName(itemName, 12), 12))
            append(padLeft(safe(grossWt), 8))
            append(padLeft(safe(netWt), 8))
            append(padLeft(safe(stoneAmt), 8))
        }
    }

    private fun summaryRow(
        sno: String,
        itemName: String,
        totalPcs: String,
        totalGrossWt: String,
        totalNetWt: String
    ): String {
        return buildString {
            append(padRight(safe(sno), 7))
            append(padRight(fitItemName(itemName, 16), 16))
            append(padLeft(safe(totalPcs), 4))
            append(padLeft(safe(totalGrossWt), 10))
            append(padLeft(safe(totalNetWt), 10))
        }
    }

    private fun summaryRowWeightStone(
        sno: String,
        itemName: String,
        totalGrossWt: String,
        totalNetWt: String,
        totalStoneAmt: String
    ): String {
        return buildString {
            append(padRight(safe(sno), 7))
            append(padRight(fitItemName(itemName, 12), 12))
            append(padLeft(safe(totalGrossWt), 8))
            append(padLeft(safe(totalNetWt), 8))
            append(padLeft(safe(totalStoneAmt), 8))
        }
    }

    private data class SummaryData(
        val itemName: String,
        val totalPcs: Int,
        val totalGrossWt: Double,
        val totalNetWt: Double
    )

    private data class SummaryDataWeightStone(
        val itemName: String,
        val totalGrossWt: Double,
        val totalNetWt: Double,
        val totalStoneAmt: Double
    )

    private fun buildSummary(items: List<DeliveryChallanItemPrint>): List<SummaryData> {
        return items
            .groupBy { safe(it.itemName, "-") }
            .map { (itemName, groupedItems) ->
                SummaryData(
                    itemName = itemName,
                    totalPcs = groupedItems.sumOf { it.pcs },
                    totalGrossWt = groupedItems.sumOf {
                        cleanWeight(it.grossWt).toDoubleOrNull() ?: 0.0
                    },
                    totalNetWt = groupedItems.sumOf {
                        cleanWeight(it.netWt).toDoubleOrNull() ?: 0.0
                    }
                )
            }
    }

    private fun buildSummaryWeightStone(items: List<DeliveryChallanItemPrint>): List<SummaryDataWeightStone> {
        return items
            .groupBy { safe(it.itemName, "-") }
            .map { (itemName, groupedItems) ->
                SummaryDataWeightStone(
                    itemName = itemName,
                    totalGrossWt = groupedItems.sumOf {
                        cleanWeight(it.grossWt).toDoubleOrNull() ?: 0.0
                    },
                    totalNetWt = groupedItems.sumOf {
                        cleanWeight(it.netWt).toDoubleOrNull() ?: 0.0
                    },
                    totalStoneAmt = groupedItems.sumOf {
                        cleanAmount(it.stoneAmt).toDoubleOrNull() ?: 0.0
                    }
                )
            }
    }

    private fun txt(
        printer: POSPrinter,
        text: String,
        align: Int = POSConst.ALIGNMENT_LEFT,
        attribute: Int = POSConst.FNT_DEFAULT,
        size: Int = POSConst.TXT_1WIDTH or POSConst.TXT_1HEIGHT
    ): POSPrinter {
        return printer.printText(text, align, attribute, size)
    }

    fun printDeliveryChallanCompact(
        data: DeliveryChallanPrintData,
        companyName: String,
        clientCode: String? = null,
        onResult: ((Boolean, String) -> Unit)? = null
    ) {
        val printer = posPrinter
        if (printer == null) {
            onResult?.invoke(false, "Printer not connected")
            return
        }

        val items = data.items
        if (items.isEmpty()) {
            onResult?.invoke(false, "No items available to print")
            return
        }

        val summaryList = buildSummary(items)
        val summaryWeightStoneList = buildSummaryWeightStone(items)
        val useWeightStoneLayout = usesLs000058PrintLayout(clientCode)
        val dateText = formatDate(data.createdDateTime)
        val phoneText = safe(data.phone, "-")
        val nameText = safe(data.customerName, "-")
        val companyText = safe(companyName, "Company")

        try {
            // Match Sparkle exactly: printText + Font A (default), not Font B / raw bytes.
            var chain = printer
                .initializePrinter()
                .selectCodePage(POSConst.CODE_PAGE_PC437)

            // Company — large centered (same as Kotlin image 2)
            chain = chain.printText(
                "$companyText\n",
                POSConst.ALIGNMENT_CENTER,
                POSConst.FNT_DEFAULT,
                POSConst.TXT_2WIDTH or POSConst.TXT_2HEIGHT
            )
            chain = hLine(chain)

            // Labels: Name/Phone LEFT, Date/Status RIGHT (same as Kotlin)
            chain = txt(chain, "Name: $nameText\n", POSConst.ALIGNMENT_LEFT)
            chain = txt(chain, "Phone : $phoneText\n", POSConst.ALIGNMENT_LEFT)
            chain = txt(chain, "Date : $dateText\n", POSConst.ALIGNMENT_RIGHT)
            chain = txt(chain, "Status : Order Summary\n", POSConst.ALIGNMENT_RIGHT)
            chain = hLine(chain)

            // Table header — exact Kotlin labels
            chain = if (useWeightStoneLayout) {
                txt(
                    chain,
                    itemRowWeightStone("Sr No", "Item Name", "G.W", "N.W", "St.Amt") + "\n"
                )
            } else {
                txt(
                    chain,
                    itemRow("Sr No", "Item Name", "PCS", "G.W", "N.W") + "\n"
                )
            }
            chain = hLine(chain)

            // Item rows
            items.forEachIndexed { index, item ->
                chain = txt(
                    chain,
                    if (useWeightStoneLayout) {
                        itemRowWeightStone(
                            sno = (index + 1).toString(),
                            itemName = safe(item.itemName, "-"),
                            grossWt = cleanWeight(item.grossWt),
                            netWt = cleanWeight(item.netWt),
                            stoneAmt = cleanAmount(item.stoneAmt)
                        )
                    } else {
                        itemRow(
                            sno = (index + 1).toString(),
                            itemName = safe(item.itemName, "-"),
                            pcs = item.pcs.toString(),
                            grossWt = cleanWeight(item.grossWt),
                            netWt = cleanWeight(item.netWt)
                        )
                    } + "\n"
                )
            }

            chain = hLine(chain)

            val grandTotalPcs = items.sumOf { it.pcs }
            val grandTotalGross = items.sumOf { cleanWeight(it.grossWt).toDoubleOrNull() ?: 0.0 }
            val grandTotalNet = items.sumOf { cleanWeight(it.netWt).toDoubleOrNull() ?: 0.0 }
            val grandTotalStoneAmt = items.sumOf { cleanAmount(it.stoneAmt).toDoubleOrNull() ?: 0.0 }

            chain = if (useWeightStoneLayout) {
                txt(
                    chain,
                    summaryRowWeightStone(
                        sno = "Total",
                        itemName = "",
                        totalGrossWt = String.format(Locale.US, "%.3f", grandTotalGross),
                        totalNetWt = String.format(Locale.US, "%.3f", grandTotalNet),
                        totalStoneAmt = String.format(Locale.US, "%.2f", grandTotalStoneAmt)
                    ) + "\n"
                )
            } else {
                txt(
                    chain,
                    summaryRow(
                        sno = "Total",
                        itemName = "",
                        totalPcs = grandTotalPcs.toString(),
                        totalGrossWt = String.format(Locale.US, "%.3f", grandTotalGross),
                        totalNetWt = String.format(Locale.US, "%.3f", grandTotalNet)
                    ) + "\n"
                )
            }

            chain = hLine(chain)
            chain = chain.feedLine()

            // Summary table — same labels as Kotlin (T.P / T.G.W / T.N.W)
            chain = if (useWeightStoneLayout) {
                txt(
                    chain,
                    summaryRowWeightStone("Sr No", "Item Name", "T.G.W", "T.N.W", "T.St.A") + "\n"
                )
            } else {
                txt(
                    chain,
                    summaryRow("Sr No", "Item Name", "T.P", "T.G.W", "T.N.W") + "\n"
                )
            }
            chain = hLine(chain)

            if (useWeightStoneLayout) {
                summaryWeightStoneList.forEachIndexed { index, summary ->
                    chain = txt(
                        chain,
                        summaryRowWeightStone(
                            sno = (index + 1).toString(),
                            itemName = summary.itemName,
                            totalGrossWt = String.format(Locale.US, "%.3f", summary.totalGrossWt),
                            totalNetWt = String.format(Locale.US, "%.3f", summary.totalNetWt),
                            totalStoneAmt = String.format(Locale.US, "%.2f", summary.totalStoneAmt)
                        ) + "\n"
                    )
                }
                val summaryGrandGross = summaryWeightStoneList.sumOf { it.totalGrossWt }
                val summaryGrandNet = summaryWeightStoneList.sumOf { it.totalNetWt }
                val summaryGrandStone = summaryWeightStoneList.sumOf { it.totalStoneAmt }
                chain = hLine(chain)
                chain = txt(
                    chain,
                    summaryRowWeightStone(
                        sno = "Total",
                        itemName = "",
                        totalGrossWt = String.format(Locale.US, "%.3f", summaryGrandGross),
                        totalNetWt = String.format(Locale.US, "%.3f", summaryGrandNet),
                        totalStoneAmt = String.format(Locale.US, "%.2f", summaryGrandStone)
                    ) + "\n"
                )
            } else {
                summaryList.forEachIndexed { index, summary ->
                    chain = txt(
                        chain,
                        summaryRow(
                            sno = (index + 1).toString(),
                            itemName = summary.itemName,
                            totalPcs = summary.totalPcs.toString(),
                            totalGrossWt = String.format(Locale.US, "%.3f", summary.totalGrossWt),
                            totalNetWt = String.format(Locale.US, "%.3f", summary.totalNetWt)
                        ) + "\n"
                    )
                }
                val summaryGrandPcs = summaryList.sumOf { it.totalPcs }
                val summaryGrandGross = summaryList.sumOf { it.totalGrossWt }
                val summaryGrandNet = summaryList.sumOf { it.totalNetWt }
                chain = hLine(chain)
                chain = txt(
                    chain,
                    summaryRow(
                        sno = "Total",
                        itemName = "",
                        totalPcs = summaryGrandPcs.toString(),
                        totalGrossWt = String.format(Locale.US, "%.3f", summaryGrandGross),
                        totalNetWt = String.format(Locale.US, "%.3f", summaryGrandNet)
                    ) + "\n"
                )
            }

            chain = hLine(chain)

            if (useWeightStoneLayout) {
                val totalAmountValue = resolvePrintTotalAmount(data, items)
                chain = chain.feedLine()
                chain = txt(
                    chain,
                    totalAmountRow(String.format(Locale.US, "%.2f", totalAmountValue)) + "\n"
                )
                chain = hLine(chain)
            }

            chain.feedLine(3)

            onResult?.invoke(true, "Printed successfully")
        } catch (e: Exception) {
            Log.e("PRINTER", "printDeliveryChallanCompact error", e)
            onResult?.invoke(false, e.message ?: "Printing failed")
        }
    }
}

fun resolvePrintHeader(
    clientCode: String?,
    companyName: String?,
    organizationName: String?
): String {
    if (clientCode.equals("LS000053", ignoreCase = true)) {
        return "Rough Estimation"
    }
    return companyName?.trim()?.takeIf { it.isNotEmpty() }
        ?: organizationName?.trim()?.takeIf { it.isNotEmpty() }
        ?: "Company"
}

fun usesLs000058PrintLayout(clientCode: String?): Boolean {
    return clientCode.equals("LS000058", ignoreCase = true)
}
