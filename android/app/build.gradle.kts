import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
}

val signingPropertiesPath = System.getenv("MEME_ANDROID_SIGNING_PROPERTIES")
val releaseSigning = signingPropertiesPath?.let { path ->
    val propertiesFile = file(path)
    require(propertiesFile.isFile) {
        "MEME_ANDROID_SIGNING_PROPERTIES must name an existing signing properties file."
    }
    Properties().apply { propertiesFile.inputStream().use(::load) }
}
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }

android {
    namespace = "dev.memesearcher.meme_searcher"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "dev.memesearcher.meme_searcher"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigning != null) {
            create("release") {
                storeFile = rootProject.file(requireNotNull(releaseSigning.getProperty("storeFile")))
                storePassword = requireNotNull(releaseSigning.getProperty("storePassword"))
                keyAlias = requireNotNull(releaseSigning.getProperty("keyAlias"))
                keyPassword = requireNotNull(releaseSigning.getProperty("keyPassword"))
            }
        }
    }
    buildTypes {
        getByName("release") {
            // A release task is rejected below when external signing is absent.
            if (releaseSigning != null) signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

gradle.taskGraph.whenReady {
    if (releaseRequested && releaseSigning == null) {
        throw GradleException("Release signing is required: set MEME_ANDROID_SIGNING_PROPERTIES to a secure properties file containing storeFile, storePassword, keyAlias, and keyPassword.")
    }
}

flutter { source = "../.." }
