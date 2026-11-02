pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    // Resolve symlinks and force an uppercase drive letter. Android Studio
    // otherwise fails to import this included build: "Missing ExternalProject for :".
    val flutterGradlePath = file("$flutterSdkPath/packages/flutter_tools/gradle")
        .canonicalFile
        .absolutePath
        .let { raw ->
            if (raw.length >= 2 && raw[1] == ':') {
                raw[0].uppercaseChar() + raw.substring(1)
            } else {
                raw
            }
        }
    includeBuild(flutterGradlePath) {
        // The Flutter tools folder is named "gradle", which collides with
        // android/gradle and leaves the IDE with an empty project path.
        name = "flutter_tools_gradle"
    }

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

rootProject.name = "android"
include(":app")
