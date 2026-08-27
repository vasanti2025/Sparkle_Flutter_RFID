package com.loyalstring.rfid.rfid_flutter

import android.app.Application
import android.util.Log
import io.flutter.FlutterInjector

/**
 * Kick off Flutter loader I/O on Application create, but never block the
 * main thread with [io.flutter.embedding.engine.loader.FlutterLoader.ensureInitializationComplete].
 * Completing init on a background thread holds the same lock FlutterActivity
 * needs — that froze the native splash for several seconds on RFID handhelds.
 */
class SparkleApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        try {
            FlutterInjector.instance().flutterLoader().startInitialization(this)
            Log.i("SparkleApplication", "Flutter startInitialization posted")
        } catch (e: Throwable) {
            Log.w("SparkleApplication", "Flutter startInitialization skipped", e)
        }
    }
}
