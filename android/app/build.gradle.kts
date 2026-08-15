plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "dev.seven_cgpalabs.codingsaathi"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        prefab = true
    }

    defaultConfig {
        applicationId = "dev.seven_cgpalabs.codingsaathi"
        minSdk = 28  // Android 9+, required for NNAPI
        targetSdk = 36
        versionCode = 2
        versionName = "2.0.0"

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
        debug {
            isMinifyEnabled = false
        }
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    
    packaging {
        jniLibs {
            keepDebugSymbols += "**/*.so"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // AndroidX Core
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    
    // Preferences (System Settings UI)
    implementation("androidx.preference:preference-ktx:1.2.1")
    
    // Lifecycle & Coroutines
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.9.1")
    implementation("androidx.lifecycle:lifecycle-service:2.9.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    
    // Jetpack Glance for Widgets (optional - using AppWidgetProvider approach)
    // implementation("androidx.glance:glance-appwidget:1.1.1")
    
    // ONNX Runtime Android — provides libonnxruntime.so (arm64) and C++ headers
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.20.0")
}
