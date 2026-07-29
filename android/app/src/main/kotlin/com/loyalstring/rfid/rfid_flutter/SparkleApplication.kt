package com.loyalstring.rfid.rfid_flutter

import android.app.Application
import android.util.Log
import io.flutter.FlutterInjector
import java.util.concurrent.Executors

/** Pre-warm Flutter native loader before MainActivity — shaves cold-start time on RFID handhelds. */
class SparkleApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Executors.newSingleThreadExecutor().execute {
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(this)
                loader.ensureInitializationComplete(this, null)
                Log.i("SparkleApplication", "Flutter loader pre-warmed")
            } catch (e: Throwable) {
                Log.w("SparkleApplication", "Flutter prewarm skipped", e)
            }
        }
        Executors.newSingleThreadExecutor().execute {
            try {
                getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE).all
            } catch (_: Throwable) {
            }
        }
    }
}
