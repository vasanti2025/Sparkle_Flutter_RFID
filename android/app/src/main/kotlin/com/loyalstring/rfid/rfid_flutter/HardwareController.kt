package com.loyalstring.rfid.rfid_flutter

import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * DeviceAPI-free surface so [MainActivity] can load RFID/barcode/tray hardware
 * only via reflection on first use (never at Activity class-load).
 */
interface HardwareController {
    fun setEventSink(sink: EventChannel.EventSink?)
    fun handleMethod(call: MethodCall, result: MethodChannel.Result)
    fun onBarcodeHardwareKey()
    fun release()
}
