import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// android/key.properties — same upload keystore already used by the Play app.
// storePassword, keyPassword, keyAlias, storeFile (path relative to android/app, or absolute).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.loyalstring.rfid.rfid_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storePassword = keystoreProperties.getProperty("storePassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
            }
        }
    }

    defaultConfig {
        // Must match the published Play Store app. Kotlin sources stay in the namespace below.
        applicationId = "com.loyalstring.rfid"
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
            isDebuggable = true
        }
        release {
            // AOT (fast open). Minify off — R8 fights Flutter Play Core stubs;
            // release AOT alone is the main cold-start win vs debug.
            isDebuggable = false
            isMinifyEnabled = false
            isShrinkResources = false
            // Play rejects an update signed with the debug key. Use the existing upload keystore.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    packaging {
        jniLibs {
            // Extract .so to disk once — faster cold start on handhelds than mmap-from-APK.
            useLegacyPackaging = true
            // Handhelds are arm64. 32-bit and x86 copies are 4 KB aligned and fail Play's 16 KB check.
            excludes += setOf(
                "lib/armeabi/**",
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/x86_64/**",
                "lib/mips/**",
                "lib/mips64/**",
                // Loaded only by the unused serial printer path. Bluetooth printing does not use it.
                "**/libprinter_serial_port.so",
            )
        }
    }
}

flutter {
    source = "../.."
}

// Plugin ships its own DeviceAPI. Keep the app AAR so the existing reader is unchanged.
configurations.configureEach {
    exclude(group = "com.rscja.deviceapi", module = "DeviceAPI")
}

dependencies {
    implementation(files("libs/DeviceAPI_V2.0.3_20260313.aar"))
    // Xprinter POSConnect Bluetooth thermal printer (Delivery Challan) — same as Sparkle Kotlin
    implementation(files("libs/printer-lib-3.2.0.aar"))
}

// Flutter CLI looks in outputs/flutter-apk/; AGP writes to outputs/apk/<variant>/.
val copyApksToFlutterOutputs = tasks.register("copyApksToFlutterOutputs") {
    doLast {
        val buildDir = layout.buildDirectory.get().asFile
        val flutterApkDir = File(buildDir, "outputs/flutter-apk")
        flutterApkDir.mkdirs()
        File(buildDir, "outputs/apk").walkTopDown()
            .filter { it.isFile && it.extension == "apk" }
            .forEach { apk ->
                apk.copyTo(File(flutterApkDir, apk.name), overwrite = true)
            }
    }
}

tasks.matching { it.name == "assembleDebug" || it.name == "assembleRelease" }.configureEach {
    finalizedBy(copyApksToFlutterOutputs)
}

// ML Kit face-detection 16.1.5 ships libface_detector_v2_jni.so with 4 KB LOAD alignment.
// Play rejects that for targetSdk 35+. Insert padding so each LOAD segment is 16 KB congruent.
// Face login still uses the same library. C5/C7 are 4 KB devices; 16 KB alignment still loads there.
fun readLe(buf: ByteArray, off: Int, size: Int): Long {
    var value = 0L
    for (i in 0 until size) {
        value = value or ((buf[off + i].toLong() and 0xff) shl (8 * i))
    }
    return value
}

fun writeLe(buf: ByteArray, off: Int, value: Long) {
    var rest = value
    for (i in 0 until 8) {
        buf[off + i] = (rest and 0xff).toByte()
        rest = rest ushr 8
    }
}

fun alignElf64LittleTo16k(input: ByteArray): ByteArray? {
    if (input.size < 64) return null
    if (input[0] != 0x7f.toByte() || input[1] != 'E'.code.toByte() ||
        input[2] != 'L'.code.toByte() || input[3] != 'F'.code.toByte()
    ) {
        return null
    }
    if (input[4].toInt() != 2 || input[5].toInt() != 1) return null
    val page = 16_384L
    var data = input
    repeat(8) {
        val phoff = readLe(data, 32, 8).toInt()
        val phentsize = readLe(data, 54, 2).toInt()
        val phnum = readLe(data, 56, 2).toInt()
        var insertAt = -1L
        var pad = 0L
        for (i in 0 until phnum) {
            val off = phoff + i * phentsize
            if (readLe(data, off, 4) != 1L) continue
            val po = readLe(data, off + 8, 8)
            val va = readLe(data, off + 16, 8)
            if (po % page == va % page) continue
            val thisPad = Math.floorMod(va % page - po % page, page)
            if (po >= insertAt) {
                insertAt = po
                pad = thisPad
            }
        }
        if (insertAt < 0L || pad == 0L) return@repeat
        val at = insertAt.toInt()
        val next = ByteArray(data.size + pad.toInt())
        System.arraycopy(data, 0, next, 0, at)
        System.arraycopy(data, at, next, at + pad.toInt(), data.size - at)
        data = next
        val shoff = readLe(data, 40, 8)
        if (shoff >= insertAt) writeLe(data, 40, shoff + pad)
        val phoff2 = readLe(data, 32, 8).toInt()
        val phentsize2 = readLe(data, 54, 2).toInt()
        val phnum2 = readLe(data, 56, 2).toInt()
        for (i in 0 until phnum2) {
            val off = phoff2 + i * phentsize2
            val pOff = readLe(data, off + 8, 8)
            if (pOff >= insertAt) writeLe(data, off + 8, pOff + pad)
        }
        val shoff2 = readLe(data, 40, 8).toInt()
        val shentsize2 = readLe(data, 58, 2).toInt()
        val shnum2 = readLe(data, 60, 2).toInt()
        for (i in 0 until shnum2) {
            val off = shoff2 + i * shentsize2
            val shOff = readLe(data, off + 24, 8)
            if (shOff >= insertAt) writeLe(data, off + 24, shOff + pad)
        }
    }
    val phoff = readLe(data, 32, 8).toInt()
    val phentsize = readLe(data, 54, 2).toInt()
    val phnum = readLe(data, 56, 2).toInt()
    for (i in 0 until phnum) {
        val off = phoff + i * phentsize
        if (readLe(data, off, 4) != 1L) continue
        if (readLe(data, off + 48, 8) < page) writeLe(data, off + 48, page)
        val po = readLe(data, off + 8, 8)
        val va = readLe(data, off + 16, 8)
        if (po % page != va % page) return null
    }
    return data
}

val patchRelease16kPageSize = tasks.register("patchRelease16kPageSize") {
    dependsOn("stripReleaseDebugSymbols")
    doLast {
        val root = layout.buildDirectory.get().asFile.resolve(
            "intermediates/stripped_native_libs/release",
        )
        if (!root.exists()) return@doLast
        root.walkTopDown()
            .filter { it.isFile && it.name == "libface_detector_v2_jni.so" && it.path.contains("arm64-v8a") }
            .forEach { so ->
                val patched = alignElf64LittleTo16k(so.readBytes()) ?: return@forEach
                if (!patched.contentEquals(so.readBytes())) {
                    so.writeBytes(patched)
                    println("Aligned ${so.name} to 16 KB page size")
                }
            }
    }
}

tasks.matching {
    it.name == "packageReleaseBundle" || it.name == "buildReleasePreBundle" || it.name == "bundleRelease"
}.configureEach {
    dependsOn(patchRelease16kPageSize)
}

