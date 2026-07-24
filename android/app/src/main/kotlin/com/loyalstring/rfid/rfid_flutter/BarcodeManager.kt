package com.loyalstring.rfid.rfid_flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.rscja.barcode.BarcodeDecoder
import com.rscja.barcode.BarcodeFactory
import com.rscja.barcode.BarcodeUtility

/**
 * Chainway hardware barcode engine — same as Sparkle [BarcodeReader].
 */
class BarcodeManager(private val context: Context) {
    companion object {
        private const val TAG = "BarcodeManager"
    }

    private val decoder: BarcodeDecoder = BarcodeFactory.getInstance().barcodeDecoder
    private val mainHandler = Handler(Looper.getMainLooper())
    private var opened = false
    private var scanListener: ((String) -> Unit)? = null

    fun setOnScanned(listener: ((String) -> Unit)?) {
        scanListener = listener
        try {
            decoder.setDecodeCallback { entity ->
                if (entity.resultCode == BarcodeDecoder.DECODE_SUCCESS) {
                    val data = entity.barcodeData?.trim().orEmpty()
                    if (data.isEmpty()) return@setDecodeCallback
                    Log.d(TAG, "Scan success: $data")
                    try {
                        BarcodeUtility.getInstance().enablePlaySuccessSound(context, true)
                    } catch (_: Throwable) {
                    }
                    mainHandler.post { scanListener?.invoke(data) }
                } else {
                    Log.e(TAG, "Scan failed code=${entity.resultCode}")
                }
            }
        } catch (e: Throwable) {
            Log.e(TAG, "setDecodeCallback failed: ${e.message}")
        }
    }

    fun openIfNeeded(): Boolean {
        if (opened) return true
        return try {
            decoder.open(context)
            opened = true
            Log.d(TAG, "Barcode decoder opened")
            true
        } catch (e: Throwable) {
            Log.e(TAG, "open failed: ${e.message}")
            false
        }
    }

    fun startScan(): Boolean {
        return try {
            if (!openIfNeeded()) return false
            decoder.startScan()
            Log.d(TAG, "startScan()")
            true
        } catch (e: Throwable) {
            Log.e(TAG, "startScan failed: ${e.message}")
            false
        }
    }

    fun stopScan() {
        try {
            decoder.stopScan()
        } catch (_: Throwable) {
        }
    }

    fun close() {
        try {
            if (opened) {
                decoder.close()
                opened = false
            }
        } catch (e: Throwable) {
            Log.e(TAG, "close failed: ${e.message}")
        }
    }
}
