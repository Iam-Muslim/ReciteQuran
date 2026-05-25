import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.recitequran.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.recitequran.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
signingConfigs {
        create("release") {
            // This reads the properties
            val storePass = keystoreProperties.getProperty("storePassword")
            val keyPass = keystoreProperties.getProperty("keyPassword")
            val alias = keystoreProperties.getProperty("keyAlias")
            val storePath = keystoreProperties.getProperty("storeFile")

            // This ensures we get a clear error if something is missing
            if (storePass == null || keyPass == null || alias == null || storePath == null) {
                throw GradleException("Key properties are missing or key.properties file was not found!")
            }

            keyAlias = alias
            keyPassword = keyPass
            storeFile = file(storePath)
            storePassword = storePass
        }
    }
    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    packaging {
        jniLibs {
            pickFirsts.add("**/libonnxruntime.so")
            pickFirsts.add("**/libc++_shared.so")
        }
    }
}

flutter {
    source = "../.."
}