allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // Set global variables for plugins to use
    project.extensions.extraProperties.set("compileSdkVersion", 36)
    project.extensions.extraProperties.set("targetSdkVersion", 36)
    project.extensions.extraProperties.set("minSdkVersion", 21)
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

subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.extensions.getByName("android")
            
            // Force compileSdk to 36 via reflection to support BAKLAVA and other Android 15 features.
            // This is applied to all subprojects (plugins) to ensure they compile with the latest SDK.
            try {
                android.javaClass.getMethod("setCompileSdk", java.lang.Integer.TYPE).invoke(android, 36)
            } catch (e: Throwable) {
                try {
                    android.javaClass.getMethod("setCompileSdkVersion", java.lang.Integer.TYPE).invoke(android, 36)
                } catch (e2: Throwable) {}
            }

            // Also force targetSdk to 36 in defaultConfig
            try {
                val defaultConfig = android.javaClass.getMethod("getDefaultConfig").invoke(android)
                try {
                    defaultConfig.javaClass.getMethod("setTargetSdk", java.lang.Integer.TYPE).invoke(defaultConfig, 36)
                } catch (e: Throwable) {
                    try {
                        defaultConfig.javaClass.getMethod("setTargetSdkVersion", java.lang.Integer.TYPE).invoke(defaultConfig, 36)
                    } catch (e2: Throwable) {}
                }
            } catch (e: Throwable) {}
            
            // Ensure namespace is set for plugins that might be missing it (prevents AGP 8+ errors)
            try {
                val getNamespace = android.javaClass.getMethod("getNamespace")
                val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                if (getNamespace.invoke(android) == null) {
                    val namespace = "com.${project.name.replace("-", ".").replace("_", ".")}"
                    setNamespace.invoke(android, namespace)
                }
            } catch (e: Throwable) {}
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
