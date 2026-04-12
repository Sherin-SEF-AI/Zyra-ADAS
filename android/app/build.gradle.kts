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

        // C++ compile flags and CMake invocation arguments, applied to
        // every buildType. Individual flags that only make sense in the
        // compiled C++ live in the top-level externalNativeBuild block.
        externalNativeBuild {
            cmake {
                // Restrict CMake configure+build to the ABIs we actually
                // ship prebuilt NCNN / OpenCV for. Without this, the AGP
                // defaults (which include armeabi-v7a + x86) cause CMake
                // to run for ABIs where third_party/<abi>/ is empty.
                abiFilters += listOf("arm64-v8a", "x86_64")
                cppFlags += listOf(
                    "-std=c++17",
                    "-fvisibility=hidden",
                    "-ffunction-sections",
                    "-fdata-sections",
                )
                arguments += listOf(
                    "-DANDROID_STL=c++_shared",
                    "-DANDROID_ARM_NEON=ON",
                    "-DANDROID_PLATFORM=android-30",
                )
            }
        }
    }

    // Native build wiring — points at the CMakeLists.txt that drives
    // libzyra_perception.so. Kept in sync with the pinned CMake version in
    // project_toolchain_versions.md.
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // Keep the NDK's libc++_shared.so from being duplicated across
    // plugin-provided .so files (camera, Flutter engine, etc.) once we link
    // our own libzyra_perception.so that also references it.
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
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
