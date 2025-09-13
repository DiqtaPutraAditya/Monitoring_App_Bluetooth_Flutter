import com.android.build.gradle.BaseExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // Set ndkVersion langsung jika modul Android
    plugins.withId("com.android.application") {
        extensions.configure<BaseExtension>("android") {
            ndkVersion = "27.0.12077973"
        }
    }
    plugins.withId("com.android.library") {
        extensions.configure<BaseExtension>("android") {
            ndkVersion = "27.0.12077973"
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
