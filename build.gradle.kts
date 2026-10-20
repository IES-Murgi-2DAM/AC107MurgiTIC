// Top-level build file where you can add configuration options common to all sub-projects/modules.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.compose) apply false
}

// -------------------------------------------------------------
// CONTROL DE ENTORNO PARA EXAMEN (Bloqueo fuera de Dev Container)
// -------------------------------------------------------------
tasks.register("verificarEntornoExamen") {
    doFirst {
        val enContenedor = System.getenv("REMOTE_CONTAINERS") != null ||
                java.io.File("/.dockerenv").exists()
        if (!enContenedor) {
            throw GradleException(
                "❌ ERROR DE EXAMEN: Estás intentando compilar fuera del Dev Container oficial.\n" +
                        "Por favor, abre el proyecto en IntelliJ y selecciona 'Reopen in Container'."
            )
        }
    }
}

// Enganchar la validación al proceso de compilación
gradle.projectsEvaluated {
    allprojects {
        tasks.matching { it.name == "preBuild" }.configureEach {
            dependsOn(":verificarEntornoExamen")
        }
    }
}