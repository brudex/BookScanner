plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.quizfactor.bookscanner.bookscanner"
    compileSdk = flutter.compileSdkVersion
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
        applicationId = "com.quizfactor.bookscanner.bookscanner"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Phone ABIs only. A fat APK that also shipped x86_64 was ~335MB
        // (emulator OpenCV + Flutter natives ~233MB). Default to arm64-only
        // (~modern phones). Add "armeabi-v7a" here only if you must support
        // very old 32-bit devices. Prefer `flutter build appbundle` for Play
        // Store (Google serves one ABI per device).
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
    }

    // Maven AARs (OpenCV, ML Kit) still merge x86/x86_64 .so files even with
    // abiFilters; strip them from the packaged APK.
    packaging {
        jniLibs {
            excludes += listOf("**/x86/**", "**/x86_64/**")
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

dependencies {
    val cameraxVersion = "1.4.1"
    implementation("androidx.camera:camera-core:$cameraxVersion")
    implementation("androidx.camera:camera-camera2:$cameraxVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraxVersion")
    implementation("androidx.lifecycle:lifecycle-process:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    // ProcessCameraProvider.getInstance() returns a real
    // com.google.common.util.concurrent.ListenableFuture; CameraX only
    // pulls in the empty listenablefuture:1.0 stub transitively, so the
    // real Guava implementation must be declared explicitly.
    implementation("com.google.guava:guava:33.4.0-android")
    // On-device Latin-script text recognition (SPEC 9.4). Chinese/Japanese/
    // Korean/Devanagari script support requires separate ML Kit artifacts
    // and is not added here (SPEC 14 open decision: "OCR languages beyond
    // English").
    implementation("com.google.mlkit:text-recognition:16.0.1")
    implementation("org.opencv:opencv:4.11.0")
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
