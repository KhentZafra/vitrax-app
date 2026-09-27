plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Processes google-services.json (below) into the native config
    // Firebase actually reads at runtime. Must come after the plugins
    // above, same ordering rule as the Flutter plugin itself.
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.vitrax_app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications requires this — without it, the
        // build fails at :app:checkDebugAarMetadata with "requires core
        // library desugaring to be enabled."
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.vitrax_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 29
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Required by the compileOptions.isCoreLibraryDesugaringEnabled
    // setting above — the version number itself isn't tied to your app,
    // it's just the desugaring library's own release.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
