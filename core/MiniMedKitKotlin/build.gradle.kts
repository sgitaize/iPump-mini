// SPDX-License-Identifier: GPL-3.0-or-later
// MiniMedKit (Kotlin) – read-only protocol library for MiniMed 700-series pumps.
// Built from apps/android (settings.gradle.kts includes it as :minimedkit).
plugins {
    id("org.jetbrains.kotlin.jvm")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

dependencies {
    testImplementation(kotlin("test-junit"))
    testImplementation("junit:junit:4.13.2")
}

tasks.test {
    // Tests that need the local SAKE key database (_vendor/keys, gitignored) are skipped without it.
    systemProperty("omp.repoRoot", rootDir.resolve("../..").canonicalPath)
    testLogging { events("passed", "skipped", "failed") }
}
