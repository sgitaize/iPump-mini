// SPDX-License-Identifier: GPL-3.0-or-later
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

val repoRoot: File = rootDir.resolve("../..").canonicalFile

/** Values from the gitignored <repo>/.env (DEV_MODE, TEST_PUMP_SERIAL), like the iOS build script. */
val dotEnv: Map<String, String> = repoRoot.resolve(".env").takeIf { it.exists() }?.readLines()
    ?.mapNotNull { line ->
        val i = line.indexOf('=')
        if (line.trimStart().startsWith("#") || i <= 0) null
        else line.substring(0, i).trim() to line.substring(i + 1).trim().trim('"', '\'')
    }?.toMap() ?: emptyMap()

/**
 * Public builds never take local files: no .env, no key database (users import it in the app).
 * Release builds are public by default (DEV_MODE=0, any pump, approved by Simon on 2026-10-15),
 * debug builds are local (DEV_MODE and test pump from .env). Override with -PompPublicBuild=0/1
 * and -PompPublicDevMode=0/1.
 */
fun isPublic(release: Boolean): Boolean =
    (findProperty("ompPublicBuild") as String?)?.let { it == "1" } ?: release

fun devMode(release: Boolean): Boolean =
    if (isPublic(release)) ((findProperty("ompPublicDevMode") as String?) ?: if (release) "0" else "1") == "1"
    else (dotEnv["DEV_MODE"] ?: "1") == "1"

fun testPumpSerial(release: Boolean): String = if (isPublic(release)) "" else dotEnv["TEST_PUMP_SERIAL"].orEmpty()

/** Optional release signing from a gitignored keystore.properties (see docs/de/android.md). */
val signingProps = Properties().apply {
    val f = rootDir.resolve("keystore.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "de.sgitaize.openminipump"
    compileSdk = 36

    defaultConfig {
        applicationId = "de.sgitaize.openminipump"
        minSdk = 29
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        if (signingProps.getProperty("storeFile") != null) {
            create("release") {
                storeFile = rootDir.resolve(signingProps.getProperty("storeFile"))
                storePassword = signingProps.getProperty("storePassword")
                keyAlias = signingProps.getProperty("keyAlias")
                keyPassword = signingProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            buildConfigField("boolean", "DEV_MODE", devMode(false).toString())
            buildConfigField("String", "TEST_PUMP_SERIAL", "\"${testPumpSerial(false)}\"")
            buildConfigField("boolean", "PUBLIC_BUILD", isPublic(false).toString())
        }
        release {
            isMinifyEnabled = false
            buildConfigField("boolean", "DEV_MODE", devMode(true).toString())
            buildConfigField("String", "TEST_PUMP_SERIAL", "\"${testPumpSerial(true)}\"")
            buildConfigField("boolean", "PUBLIC_BUILD", isPublic(true).toString())
            signingConfig = signingConfigs.findByName("release")
        }
    }

    // Local (non-public) builds embed the key database from the gitignored _vendor/keys/.
    sourceSets {
        if (!isPublic(false)) getByName("debug").assets.srcDir(layout.buildDirectory.dir("generated/omp-keydb"))
        if (!isPublic(true)) getByName("release").assets.srcDir(layout.buildDirectory.dir("generated/omp-keydb"))
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    androidResources {
        generateLocaleConfig = true
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

val copyKeyDatabase by tasks.registering(Copy::class) {
    from(repoRoot.resolve("_vendor/keys")) { include("mobile-pump.keydb.hex") }
    into(layout.buildDirectory.dir("generated/omp-keydb"))
    doLast {
        if (!repoRoot.resolve("_vendor/keys/mobile-pump.keydb.hex").exists()) {
            logger.warn("Schlüsseldatenbank fehlt (_vendor/keys/mobile-pump.keydb.hex) – Import in der App nötig.")
        }
    }
}
tasks.named("preBuild") { dependsOn(copyKeyDatabase) }

tasks.withType<Test>().configureEach {
    // Screenshots of the screens with demo data: ./gradlew :app:testDebugUnitTest -Pscreenshots=<dir>
    systemProperty("roborazzi.test.record", "true")
    (findProperty("screenshots") as String?)?.let { systemProperty("omp.screenshots", it) }
}

dependencies {
    implementation(project(":minimedkit"))

    val composeBom = platform("androidx.compose:compose-bom:2025.12.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.12.4")
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.4")
    implementation("androidx.lifecycle:lifecycle-service:2.9.4")
    debugImplementation("androidx.compose.ui:ui-tooling")

    testImplementation("junit:junit:4.13.2")
    testImplementation(kotlin("test-junit"))
    // Screen rendering without device/emulator (Robolectric native graphics + Roborazzi).
    testImplementation("org.robolectric:robolectric:4.16")
    testImplementation("io.github.takahirom.roborazzi:roborazzi:1.74.0")
    testImplementation("io.github.takahirom.roborazzi:roborazzi-compose:1.74.0")
    testImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
