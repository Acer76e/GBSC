plugins {
    id("com.android.application")
}

android {
    namespace = "com.acer76e.studyquiz"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.acer76e.studyquiz.sample"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0-sample"
    }

    buildTypes {
        // Debug-signed on purpose: this build is sideloaded, not shipped
        // through a store, so the auto-generated debug key is all it needs.
        getByName("debug") {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation("androidx.webkit:webkit:1.12.1")
}
