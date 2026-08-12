plugins {
    id("com.android.application")
}

android {
    namespace = "dev.seven_cgpalabs.codingsaathi"
    compileSdk = 35
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        // Required for CMake to consume ONNX Runtime headers and .so from the AAR
        prefab = true
    }

    defaultConfig {
        applicationId = "dev.seven_cgpalabs.codingsaathi"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"

        ndk {
            //noinspection ChromeOsAbiSupport
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }

        externalNativeBuild {
            cmake {
                arguments += listOf("-DANDROID_STL=c++_shared")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // ONNX Runtime Android — provides libonnxruntime.so (arm64) and C++ headers
    // via the prefab mechanism. CMake links against onnxruntime::onnxruntime.
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.20.0")

    // AndroidX Preference for System Settings UI (PreferenceFragmentCompat)
    implementation("androidx.preference:preference-ktx:1.2.1")

    // AndroidX AppCompat for AppPreferenceActivity
    implementation("androidx.appcompat:appcompat:1.7.0")

    // FileProvider for log sharing
    implementation("androidx.core:core-ktx:1.13.1")
}
