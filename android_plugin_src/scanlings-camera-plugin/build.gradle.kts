plugins {
    id("com.android.library")
    kotlin("android")
}

android {
    namespace = "com.scanlings.camera"
    compileSdk = 34

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // Godot Android library is provided by the export template environment.
    compileOnly(files("libs/godot-lib.aar"))

    // Needed for FileProvider
    implementation("androidx.core:core-ktx:1.12.0")
}
