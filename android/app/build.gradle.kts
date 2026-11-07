import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
if (signingPropertiesFile.isFile) {
    signingPropertiesFile.inputStream().use { signingProperties.load(it) }
}

fun signingValue(property: String, environment: String): String? =
    providers.environmentVariable(environment).orNull?.takeIf { it.isNotEmpty() }
        ?: signingProperties.getProperty(property)?.takeIf { it.isNotEmpty() }

val releaseStoreFile = signingValue("storeFile", "CACOMIXTLE_STORE_FILE")
val releaseStorePassword = signingValue("storePassword", "CACOMIXTLE_STORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "CACOMIXTLE_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "CACOMIXTLE_KEY_PASSWORD")
val missingSigningValues = mapOf(
    "storeFile / CACOMIXTLE_STORE_FILE" to releaseStoreFile,
    "storePassword / CACOMIXTLE_STORE_PASSWORD" to releaseStorePassword,
    "keyAlias / CACOMIXTLE_KEY_ALIAS" to releaseKeyAlias,
    "keyPassword / CACOMIXTLE_KEY_PASSWORD" to releaseKeyPassword,
).filterValues { it == null }.keys
val allowUnsignedRelease =
    providers.environmentVariable("CACOMIXTLE_ALLOW_UNSIGNED_RELEASE").orNull == "true"

android {
    namespace = "com.shaka.cacomixtlePad"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }
    defaultConfig {
        applicationId = "com.shaka.cacomixtlePad"
        minSdk = 21
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        if (!allowUnsignedRelease && missingSigningValues.isEmpty()) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }
    buildTypes {
        release {
            signingConfig = if (allowUnsignedRelease || missingSigningValues.isNotEmpty())
                null else signingConfigs.getByName("release")
        }
    }
}

val validateReleaseSigning by tasks.registering {
    doLast {
        if (!allowUnsignedRelease) {
            if (missingSigningValues.isNotEmpty()) {
                throw GradleException(
                    "Release signing is not configured. Missing: " +
                        missingSigningValues.joinToString() +
                        ". See docs/RELEASE.md and android/key.properties.example. " +
                        "Use a debug build for testing."
                )
            }
            if (!rootProject.file(releaseStoreFile!!).isFile) {
                throw GradleException("Release keystore not found. See docs/RELEASE.md.")
            }
        }
    }
}

tasks.configureEach {
    if (name == "preReleaseBuild") dependsOn(validateReleaseSigning)
}

flutter {
    source = "../.."
}
