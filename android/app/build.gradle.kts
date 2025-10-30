import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin") // Flutter debe ir al final
    id("com.google.gms.google-services")
}

// 🔐 Carga del archivo key.properties
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.yendoo_app"
    compileSdk = 35
    ndkVersion = "27.0.12077973" // ✅ Versión correcta

    defaultConfig {
        applicationId = "com.yendoo_app" // ✅ Coincide con Firebase
        minSdk = 24
        targetSdk = 35
        versionCode = 102
        versionName = "1.0.3"
    }

    signingConfigs {
        create("release") {
            val storeFileProp = keystoreProperties["storeFile"]?.toString()
            if (storeFileProp != null) {
                storeFile = file(storeFileProp)
            }
            storePassword = keystoreProperties["storePassword"]?.toString()
            keyAlias = keystoreProperties["keyAlias"]?.toString()
            keyPassword = keystoreProperties["keyPassword"]?.toString()
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }
}

flutter {
    source = "../.."
}
