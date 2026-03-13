
plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}
import java.util.Properties

val localProps = Properties().apply {
    val f = project.rootProject.file("local.properties") // ✅ 명확히 rootProject
    if (f.exists()) f.inputStream().use { load(it) }
}

val mapsKey: String = localProps.getProperty("MAPS_API_KEY") ?: ""

if (mapsKey.isBlank()) {
    throw GradleException("MAPS_API_KEY is missing. Put it in android/local.properties as MAPS_API_KEY=YOUR_KEY")
}

android {
    namespace = "com.example.spotly"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.spotly"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        resValue("string", "google_maps_key", mapsKey)
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
