allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()

rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// unified_esc_pos_printer 3.4.0 (latest) hardcodes compileSdk = 34, but its
// network_info_plus dependency demands 36, and AGP 9's release AAR-metadata
// check fails the build on that. Raise it here until upstream does; drop this
// block once the plugin's own android/build.gradle names 36 or later.
subprojects {
    if (name == "unified_esc_pos_printer") {
        afterEvaluate {
            extensions.configure<com.android.build.api.dsl.LibraryExtension> {
                compileSdk = 36
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
