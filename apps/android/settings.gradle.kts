// SPDX-License-Identifier: GPL-3.0-or-later
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "iPump-mini"
include(":app")
// Shared protocol library (Kotlin port of core/MiniMedKit), plain JVM so its tests run without Android.
include(":minimedkit")
project(":minimedkit").projectDir = file("../../core/MiniMedKitKotlin")
