plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.lantern.lantern"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        // Diagnostic variant (-P lanternGles=1, via flutter build
        // --android-project-arg): its own package so both install side by
        // side, with Impeller on its OpenGL ES backend instead of Vulkan.
        val gles = (project.findProperty("lanternGles") as String?) == "1"
        // Build tag (-P lanternTag=m7.2, set by tools/build_apk.sh): each
        // tagged build is its own app, "Lantern m7.2" with package
        // dev.lantern.lantern.m7_2, so several versions install side by side
        // on the phone for comparison. No tag: the plain "Lantern".
        val tag = (project.findProperty("lanternTag") as String?)?.trim().orEmpty()
        val tagId = tag.lowercase().replace(Regex("[^a-z0-9]"), "_").let {
            if (it.isEmpty() || it[0].isLetter()) it else "v$it"
        }
        var appId = "dev.lantern.lantern"
        if (gles) appId += ".gles"
        if (tagId.isNotEmpty()) appId += ".$tagId"
        applicationId = appId
        manifestPlaceholders["impellerBackend"] = if (gles) "opengles" else "vulkan"
        manifestPlaceholders["appLabel"] = listOfNotNull("Lantern", tag.ifEmpty { null }, if (gles) "GLES" else null).joinToString(" ")
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 29
        targetSdk = 36
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        // arm64-only: drop other ABIs that plugin helper libraries bring along.
        jniLibs {
            excludes += listOf("lib/armeabi-v7a/**", "lib/x86_64/**", "lib/x86/**")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}


