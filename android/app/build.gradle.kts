// android/app/build.gradle.kts
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")              // ✅ plugin correcto en Kotlin DSL
    id("dev.flutter.flutter-gradle-plugin")         // Flutter al final
    id("com.google.gms.google-services")
}

// 🔐 Keystore (si usás firma propia además de Play App Signing)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.yendoo_app"
    compileSdk = 36
    ndkVersion = "28.1.13356709"

    defaultConfig {
        applicationId = "com.yendoo_app"           // ⚠️ no cambiar
        minSdk = 24
        targetSdk = 35

        // ⬆️ Subí la versión para la actualización
        versionCode = 116                           // ← mayor que 102
        versionName = "1.0.5"

        multiDexEnabled = true
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
        debug {
            // nada especial
        }
    }

    // ✅ Java 17 + DESUGARING (requerido por flutter_local_notifications modernas)
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true        // ← clave para evitar el error de AAR metadata
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ Necesario por isCoreLibraryDesugaringEnabled
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.3")

    // (opcional) si llegás a 64K métodos
    implementation("androidx.multidex:multidex:2.0.1")
}
