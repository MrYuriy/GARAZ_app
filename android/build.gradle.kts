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
// flutter_secure_storage 11 asks for compileSdk 37, which AGP looks up as
// "android-37"; the SDK now names that platform "android-37.0", so the build
// cannot find it. Its code needs nothing past 36: compile it against 36.
subprojects {
    afterEvaluate {
        if (name == "flutter_secure_storage") {
            extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)?.compileSdk = 36
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
