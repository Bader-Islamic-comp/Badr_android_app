pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")

// The Unity character room, exported by
// `unity/Assets/Companion/Editor/CompanionRoomBuilder.cs` into `unity/export`.
// MainActivity implements Unity's host interfaces, so this is required rather
// than optional: fail with an actionable message instead of a missing symbol.
val unityLibrary = file("../unity/export/unityLibrary")
require(unityLibrary.isDirectory) {
    "No Unity export at ${unityLibrary.path}. Run CompanionRoomBuilder.ExportAndroidBatch first."
}
run {
    include(":unityLibrary")
    project(":unityLibrary").projectDir = unityLibrary

    // The exported module reads `unityStreamingAssets` and `unity.*` properties
    // that live in the export's own gradle.properties, which this build never
    // loads. They include absolute SDK and NDK paths for the machine that ran
    // the export, so they are read from the export rather than committed here.
    val exported = java.util.Properties()
    file("../unity/export/gradle.properties").inputStream().use { exported.load(it) }
    gradle.beforeProject {
        if (path == ":unityLibrary") {
            exported.forEach { key, value ->
                val name = key.toString()
                if (name.startsWith("unity")) extensions.extraProperties[name] = value
            }
        }
    }
}
