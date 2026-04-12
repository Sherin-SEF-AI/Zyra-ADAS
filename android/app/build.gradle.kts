plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.zyra.mobile"
    compileSdk = 36
    ndkVersion = "27.2.12479018"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.zyra.mobile"
        minSdk = 30
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Only build 64-bit ABIs — modern Android phones are all arm64-v8a;
        // x86_64 kept for emulator dev. Drop x86_64 in release to cut APK size.
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }

        // NOTE: externalNativeBuild (C++ compile flags + CMake wiring) is
        // added in Phase 2 once android/app/src/main/cpp/CMakeLists.txt
        // exists. Adding it earlier causes Gradle configuration to fail
        // because the referenced CMakeLists.txt is absent.
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
        }
        release {
            // TODO: replace with a real signing config before shipping.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // Avoid duplicate libc++_shared across plugin .so files.
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }
}

flutter {
    source = "../.."
}
