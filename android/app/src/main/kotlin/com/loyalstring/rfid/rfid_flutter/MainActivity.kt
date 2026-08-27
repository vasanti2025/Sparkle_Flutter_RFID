package com.loyalstring.rfid.rfid_flutter

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.KeyEvent
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.util.Base64
import java.io.File
import java.util.concurrent.Executors

/**
 * Splash-safe Activity: no Chainway DeviceAPI types in fields or imports.
 * RFID/barcode/tray load only via [hw] reflection on first UHF method / key use.
 */
class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.loyalstring.rfid/uhf"
    private val BOOTSTRAP_CHANNEL = "com.loyalstring.rfid/bootstrap"
    private val EVENT_CHANNEL = "com.loyalstring.rfid/tags"
    private val PDF_CHANNEL = "com.loyalstring.rfid/pdf"
    private val PRINTER_CHANNEL = "com.loyalstring.rfid/printer"

    private var eventSink: EventChannel.EventSink? = null
    private var hardware: HardwareController? = null
    private var printerManager: Any? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var posConnectInited = false
    private var launchLoggedIn: Boolean? = null
    private var launchUsername: String = ""
    private var launchPassword: String = ""

    private fun ensureLaunchPrefsRead() {
        if (launchLoggedIn != null) return
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            fun readBool(key: String): Boolean {
                val full = "flutter.$key"
                return try {
                    prefs.getBoolean(full, false)
                } catch (_: ClassCastException) {
                    val raw = prefs.getString(full, null)?.trim()?.lowercase()
                    raw == "true" || raw == "1"
                }
            }
            fun readString(key: String): String {
                val full = "flutter.$key"
                return try {
                    prefs.getString(full, "") ?: ""
                } catch (_: ClassCastException) {
                    ""
                }
            }
            val loggedIn = readBool("logged_in")
            val rememberMe = readBool("remember_me")
            val employee = readString("employee")
            launchLoggedIn = loggedIn || employee.isNotBlank()
            launchUsername = if (rememberMe) readString("remember_username") else ""
            launchPassword = if (rememberMe) readString("remember_password") else ""
        } catch (_: Throwable) {
            launchLoggedIn = false
            launchUsername = ""
            launchPassword = ""
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        ensureLaunchPrefsRead()
        // Native LaunchTheme stays until Flutter's first frame (Login/Home).
        // Never load DeviceAPI / POSConnect here.
        super.onCreate(savedInstanceState)
    }

    private fun encodeDartArg(value: String): String {
        if (value.isEmpty()) return ""
        return Base64.encodeToString(value.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
    }

    /**
     * Pass login hint into Dart before prefs finish — first frame can be Login/Home.
     * Flutter SharedPreferences keys are stored as "flutter.<key>".
     */
    override fun getDartEntrypointArgs(): MutableList<String> {
        ensureLaunchPrefsRead()
        return mutableListOf(
            if (launchLoggedIn == true) "dashboard" else "login",
            encodeDartArg(launchUsername),
            encodeDartArg(launchPassword),
        )
    }

    /** Fast synchronous read for Dart instant boot — keys match PrefService (no flutter. prefix). */
    private fun readBootstrapSnapshot(): Map<String, Any?> {
        return try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            fun s(key: String): String? {
                val full = "flutter.$key"
                return try {
                    prefs.getString(full, null)
                } catch (_: ClassCastException) {
                    null
                }
            }
            fun b(key: String, default: Boolean = false): Boolean {
                val full = "flutter.$key"
                return try {
                    prefs.getBoolean(full, default)
                } catch (_: ClassCastException) {
                    val raw = prefs.getString(full, null)?.trim()?.lowercase()
                    raw == "true" || raw == "1"
                }
            }
            fun iOpt(key: String): Int? {
                val full = "flutter.$key"
                if (!prefs.contains(full)) return null
                return try {
                    prefs.getInt(full, 0)
                } catch (_: ClassCastException) {
                    prefs.getString(full, null)?.toIntOrNull()
                }
            }
            val employee = s("employee")
            val snap = hashMapOf<String, Any?>(
                "logged_in" to (b("logged_in") || !employee.isNullOrBlank()),
                "remember_me" to b("remember_me"),
                "remember_username" to (s("remember_username") ?: ""),
                "remember_password" to (s("remember_password") ?: ""),
                "remember_rfidType" to (s("remember_rfidType") ?: "webreusable"),
                "app_language" to (s("app_language") ?: "en"),
                "token" to s("token"),
                "employee" to employee,
                "client" to s("client"),
                "branch_id" to iOpt("branch_id"),
                "user_id" to iOpt("user_id"),
                "organisation_name" to (s("organisation_name") ?: ""),
                "custom_api_url" to s("custom_api_url"),
                "branch_ids" to s("branch_ids"),
                "tray_mode_enabled" to b("tray_mode_enabled"),
                "tray_device_address" to (s("tray_device_address") ?: ""),
                "r6_mode_enabled" to b("r6_mode_enabled"),
                "r6_device_address" to (s("r6_device_address") ?: ""),
            )
            for (key in listOf(
                    "product_count", "inventory_count", "search_count",
                    "orders_count", "stock_transfer_count",
                )) {
                iOpt(key)?.let { snap[key] = it }
            }
            snap
        } catch (_: Throwable) {
            hashMapOf<String, Any?>()
        }
    }

    /**
     * Lazy-loads [HardwareControllerImpl] via Class.forName so DeviceAPI native
     * libs are not linked when MainActivity itself is class-loaded.
     */
    private fun hw(): HardwareController {
        val existing = hardware
        if (existing != null) return existing
        val clazz = Class.forName("com.loyalstring.rfid.rfid_flutter.HardwareControllerImpl")
        val inst = clazz.getConstructor(FlutterActivity::class.java)
            .newInstance(this) as HardwareController
        inst.setEventSink(eventSink)
        hardware = inst
        return inst
    }

    private fun printer(): PrinterManager {
        val existing = printerManager as? PrinterManager
        if (existing != null) return existing
        if (!posConnectInited) {
            try {
                // Reflection so POSConnect native libs are not linked at splash.
                val clazz = Class.forName("net.posprinter.POSConnect")
                clazz.getMethod("init", android.content.Context::class.java)
                    .invoke(null, applicationContext)
                posConnectInited = true
                Log.i("MainActivity", "POSConnect.init done (lazy)")
            } catch (e: Throwable) {
                Log.e("MainActivity", "POSConnect.init failed", e)
            }
        }
        val pm = PrinterManager(this)
        printerManager = pm
        return pm
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BOOTSTRAP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSnapshot" -> result.success(readBootstrapSnapshot())
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            // Optimistic support check — never touch DeviceAPI at splash / dashboard.
            if (call.method == "isSupported") {
                result.success(true)
                return@setMethodCallHandler
            }
            try {
                hw().handleMethod(call, result)
            } catch (e: Throwable) {
                Log.e("MainActivity", "UHF channel ${call.method} failed", e)
                result.error("HARDWARE", e.message ?: "Hardware error", null)
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    // Do not force-load hardware just because Flutter listened.
                    hardware?.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    hardware?.setEventSink(null)
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PDF_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openPdf" -> {
                    val path = call.argument<String>("path").orEmpty()
                    result.success(openPdfPreview(path))
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRINTER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "listBondedPrinters" -> {
                    Executors.newSingleThreadExecutor().execute {
                        val payload = listBondedPrinterDevicesPayload()
                        mainHandler.post { result.success(payload) }
                    }
                }
                "connectPrinter" -> {
                    val address = call.argument<String>("address").orEmpty()
                    if (address.isEmpty()) {
                        result.success(mapOf("ok" to false, "message" to "Missing address"))
                        return@setMethodCallHandler
                    }
                    ensureBluetoothPermissions()
                    Executors.newSingleThreadExecutor().execute {
                        var replied = false
                        fun reply(ok: Boolean, msg: String) {
                            if (replied) return
                            replied = true
                            mainHandler.post {
                                result.success(mapOf("ok" to ok, "message" to msg))
                            }
                        }
                        try {
                            printer().connectBluetooth(address) { ok, msg ->
                                reply(ok, msg)
                            }
                            mainHandler.postDelayed({
                                reply(false, "Bluetooth connection timed out")
                            }, 18000)
                        } catch (e: Throwable) {
                            Log.e("MainActivity", "connectPrinter", e)
                            reply(false, e.message ?: "Bluetooth printer connection failed")
                        }
                    }
                }
                "disconnectPrinter" -> {
                    (printerManager as? PrinterManager)?.disconnect()
                    result.success(true)
                }
                "isPrinterConnected" -> {
                    result.success((printerManager as? PrinterManager)?.isConnected() == true)
                }
                "printDeliveryChallan" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    Executors.newSingleThreadExecutor().execute {
                        var replied = false
                        fun reply(ok: Boolean, msg: String) {
                            if (replied) return
                            replied = true
                            mainHandler.post {
                                result.success(mapOf("ok" to ok, "message" to msg))
                            }
                        }
                        try {
                            val printData = challanPrintFromArgs(args)
                            val company = args["companyName"]?.toString().orEmpty()
                            val clientCode = args["clientCode"]?.toString()
                            val header = resolvePrintHeader(
                                clientCode,
                                company,
                                args["organizationName"]?.toString(),
                            )
                            printer().printDeliveryChallanCompact(printData, header, clientCode) { ok, msg ->
                                reply(ok, msg ?: if (ok) "Printed successfully" else "Printing failed")
                            }
                            mainHandler.postDelayed({
                                reply(false, "Print timed out")
                            }, 40000)
                        } catch (e: Throwable) {
                            Log.e("MainActivity", "printDeliveryChallan", e)
                            reply(false, e.message ?: "Printing failed")
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun openPdfPreview(path: String): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false
            val uri: Uri = FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.provider",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/pdf")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e("MainActivity", "openPdfPreview failed", e)
            false
        }
    }

    private fun listBondedPrinterDevicesPayload(): Map<String, Any> {
        if (!hasPrinterBluetoothPermission()) {
            ensureBluetoothPermissions()
            return mapOf(
                "devices" to emptyList<Map<String, String>>(),
                "hasPermission" to false,
                "bluetoothEnabled" to true,
                "message" to "Please grant Bluetooth permissions",
            )
        }
        return try {
            @Suppress("DEPRECATION")
            val adapter = BluetoothAdapter.getDefaultAdapter()
            if (adapter == null) {
                return mapOf(
                    "devices" to emptyList<Map<String, String>>(),
                    "hasPermission" to true,
                    "bluetoothEnabled" to false,
                    "message" to "Bluetooth not supported",
                )
            }
            if (!adapter.isEnabled) {
                return mapOf(
                    "devices" to emptyList<Map<String, String>>(),
                    "hasPermission" to true,
                    "bluetoothEnabled" to false,
                    "message" to "Please turn on Bluetooth",
                )
            }
            val devices = adapter.bondedDevices.orEmpty().map { device: BluetoothDevice ->
                val name = try {
                    device.name?.trim()?.takeIf { it.isNotEmpty() } ?: "Bluetooth Device"
                } catch (_: SecurityException) {
                    "Bluetooth Device"
                }
                mapOf(
                    "name" to name,
                    "address" to (device.address ?: ""),
                )
            }.filter { it["address"]!!.isNotEmpty() }
            mapOf(
                "devices" to devices,
                "hasPermission" to true,
                "bluetoothEnabled" to true,
                "message" to if (devices.isEmpty()) "No paired Bluetooth devices found" else "",
            )
        } catch (e: Exception) {
            Log.e("MainActivity", "listBondedPrinterDevicesPayload", e)
            mapOf(
                "devices" to emptyList<Map<String, String>>(),
                "hasPermission" to true,
                "bluetoothEnabled" to true,
                "message" to (e.message ?: "Failed to list Bluetooth devices"),
            )
        }
    }

    private fun hasPrinterBluetoothPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            @Suppress("DEPRECATION")
            val bt = ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH) ==
                PackageManager.PERMISSION_GRANTED
            val admin = ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADMIN) ==
                PackageManager.PERMISSION_GRANTED
            val loc = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
            bt && admin && loc
        }
    }

    private fun ensureBluetoothPermissions() {
        val has = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            @Suppress("DEPRECATION")
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH) ==
                PackageManager.PERMISSION_GRANTED &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        }
        if (has) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.ACCESS_FINE_LOCATION,
                ),
                2401,
            )
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.BLUETOOTH,
                    Manifest.permission.BLUETOOTH_ADMIN,
                    Manifest.permission.ACCESS_FINE_LOCATION,
                ),
                2401,
            )
        }
    }

    private fun challanPrintFromArgs(args: Map<*, *>): DeliveryChallanPrintData {
        val itemsRaw = args["items"] as? List<*> ?: emptyList<Any>()
        val items = itemsRaw.mapNotNull { raw ->
            val m = raw as? Map<*, *> ?: return@mapNotNull null
            DeliveryChallanItemPrint(
                itemName = m["itemName"]?.toString().orEmpty(),
                purity = m["purity"]?.toString().orEmpty(),
                pcs = (m["pcs"] as? Number)?.toInt()
                    ?: m["pcs"]?.toString()?.toIntOrNull()
                    ?: 1,
                grossWt = m["grossWt"]?.toString() ?: "0",
                stoneWt = m["stoneWt"]?.toString() ?: "0",
                netWt = m["netWt"]?.toString() ?: "0",
                stoneAmt = m["stoneAmt"]?.toString() ?: "0.00",
                ratePerGram = m["ratePerGram"]?.toString() ?: "0",
                wastage = m["wastage"]?.toString() ?: "0",
                itemAmount = m["itemAmount"]?.toString() ?: "0",
            )
        }
        return DeliveryChallanPrintData(
            branchName = args["branchName"]?.toString().orEmpty(),
            city = args["city"]?.toString().orEmpty(),
            createdDateTime = args["createdDateTime"]?.toString().orEmpty(),
            customerName = args["customerName"]?.toString().orEmpty(),
            quotationNo = args["quotationNo"]?.toString().orEmpty(),
            phone = args["phone"]?.toString().orEmpty(),
            items = items,
            taxableAmount = args["taxableAmount"]?.toString() ?: "0",
            cgstPercent = (args["cgstPercent"] as? Number)?.toDouble() ?: 0.0,
            cgstAmount = args["cgstAmount"]?.toString() ?: "0",
            sgstPercent = (args["sgstPercent"] as? Number)?.toDouble() ?: 0.0,
            sgstAmount = args["sgstAmount"]?.toString() ?: "0",
            totalNetAmount = args["totalNetAmount"]?.toString()
                ?: args["totalAmount"]?.toString()
                ?: "0",
        )
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == 293 || keyCode == 280 || keyCode == 139) {
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            when (event.keyCode) {
                139 -> {
                    try {
                        hw().onBarcodeHardwareKey()
                    } catch (e: Throwable) {
                        Log.e("MainActivity", "barcode key failed", e)
                    }
                    return true
                }
                280, 293 -> {
                    runOnUiThread {
                        eventSink?.success("TRIGGER_CLICK")
                    }
                    return true
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onDestroy() {
        hardware?.release()
        hardware = null
        (printerManager as? PrinterManager)?.disconnect()
        printerManager = null
        super.onDestroy()
    }
}
