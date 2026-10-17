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

    // Inyecta CallbackToFutureAdapter directamente en el plugin camera_android_camerax
    pluginManager.withPlugin("com.android.library") {
        dependencies {
            add("implementation", "androidx.concurrent:concurrent-futures:1.2.0")
            add("implementation", "com.google.guava:listenablefuture:1.0")
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}