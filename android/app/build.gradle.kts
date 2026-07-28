plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.loyalstring.rfid.rfid_flutter"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.loyalstring.rfid.rfid_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // RFID handheld (C71) is arm64 — skip x86/x86_64 CMake builds that lock .cxx caches on Windows.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        debug {
            // Debug/JIT is 5–20x slower to open than release. Use release for real devices.
            isDebuggable = false
        }
        release {
            // AOT (fast open). Minify off — R8 fights Flutter Play Core stubs;
            // release AOT alone is the main cold-start win vs debug.
            isDebuggable = false
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs {
            // Extract .so to disk once — faster cold start on handhelds than mmap-from-APK.
            useLegacyPackaging = true
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(files("libs/DeviceAPI_ver20250209_release.aar"))
    // Xprinter POSConnect Bluetooth thermal printer (Delivery Challan) — same as Sparkle Kotlin
    implementation(files("libs/printer-lib-3.2.0.aar"))
}

