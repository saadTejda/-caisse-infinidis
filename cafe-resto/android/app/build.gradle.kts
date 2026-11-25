plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val restoKeystore = System.getenv("CAISSE_RESTO_KEYSTORE_FILE")
val restoKeystorePassword = System.getenv("CAISSE_RESTO_KEYSTORE_PASSWORD")
val hasReleaseKey = !restoKeystore.isNullOrBlank()

android {
    namespace = "com.caferesto.cafe_resto_caisse"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.caferesto.cafe_resto_caisse"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        // La tablette Lenovo est sous Android 11. Une cible plus récente
        // fait fermer son installateur sans message.
        targetSdk = 30
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // v1 est nécessaire sur les tablettes Lenovo. AGP l’enlève quand minSdk
        // est 24 : le workflow la réajoute avec apksigner après la construction.
        getByName("debug") {
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
        }
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(restoKeystore!!)
                storePassword = restoKeystorePassword
                keyAlias = System.getenv("CAISSE_RESTO_KEY_ALIAS") ?: "cafe-resto"
                keyPassword = restoKeystorePassword
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    androidComponents {
        onVariants { variant ->
            variant.signingConfig?.enableV1Signing?.set(true)
            variant.signingConfig?.enableV2Signing?.set(true)
            variant.signingConfig?.enableV3Signing?.set(true)
        }
    }

    packaging {
        jniLibs {
            // Compresse les .so. Sans ça, l’installation depuis Fichiers échoue
            // sur les tablettes qui n’acceptent pas les bibliothèques 16 Ko.
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // Clé fixe si CAISSE_RESTO_KEYSTORE_FILE est défini (GitHub Actions).
            // Sinon, clé de test Flutter : il faut désinstaller l’app avant une mise à jour signée.
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
