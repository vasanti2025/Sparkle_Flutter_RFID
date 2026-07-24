package com.loyalstring.rfid.rfid_flutter
import java.io.Serializable

data class DeliveryChallanItemPrint(  val itemName: String,
                                      val purity: String,
                                      val pcs: Int,
                                      val grossWt: String,
                                      val stoneWt: String,
                                      val netWt: String,
                                      val stoneAmt: String = "0.00",
                                      val ratePerGram: String,
                                      val wastage: String,
                                      val itemAmount: String): Serializable

data class DeliveryChallanPrintData(
    val branchName: String,
    val city: String,
    val createdDateTime: String,
    val customerName: String,
    val quotationNo: String,
    val phone: String,
    val items: List<DeliveryChallanItemPrint>,
    val taxableAmount: String,
    val cgstPercent: Double,
    val cgstAmount: String,
    val sgstPercent: Double,
    val sgstAmount: String,
    val totalNetAmount: String
): Serializable

