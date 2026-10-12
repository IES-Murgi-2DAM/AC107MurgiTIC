package es.murgitic.ac107

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import es.murgitic.ac107.ui.theme.AC107MurgiTICTheme

// Definimos una lista local de lecturas de los sensores, tanto de temperatura como de humedad, para poder
// ir haciendo pruebas del código. Los ejemplos serán cosas como "Lectura Sensor 1: 25.3ºC" o "Lectura Sensor 2: 60% humedad"
// Se puede hacer el código con los valores estáticos en una lista y una función auxiliar (como map) que construya las cadenas
val temps = listOf(25.3, 26.1, 24.8, 27.0, 25.5)
val humids = listOf(60, 55, 65, 70, 58)

val sensorReadings = temps.map { temp -> "Lectura Sensor 1: ${temp}ºC" }
    .plus(humids.map { humid -> "Lectura Sensor 2: ${humid}% humedad" })

// Ahora creamos una función "generadora" que nos devuelva una lectura aleatora de la lista sensorReadings,
// para simular la lectura de un sensor real. Esta función se llamará getRandomSensorReading y devolverá un String
fun getRandomSensorReading(): String {
    return sensorReadings.random()
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            AC107MurgiTICTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    SensorScreen(
                        modifier = Modifier.padding(innerPadding)
                    )
                }
            }
        }
    }
}

@Composable
fun SensorScreen(modifier: Modifier = Modifier) {
    // Asigno un estado mutable a la variable actualReading, que se inicializa con el valor "Sin consultar"
    val actualReading = remember { mutableStateOf("Sin consultar") }
    val isLoading = remember { mutableStateOf(false) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(text = "Sensor MurgiTIC")
        // Si el sensor está cargando, mostramos un indicador de carga, si no, mostramos la lectura actual
        if (isLoading.value) {
            LoadingIndicator()
        } else {
            Text(text = actualReading.value)
        }

        Button(
            enabled = !isLoading.value,
            onClick = {
                isLoading.value = true
                // Simulamos una consulta al sensor con un retraso de 2 segundos
                // Vosotros tendréis que implementar esto con una corrutina y un delay,
                // como hemos dado en clase.n clase.
                Handler(Looper.getMainLooper()).postDelayed({
                    actualReading.value = getRandomSensorReading()
                    isLoading.value = false
                }, 2000)
        }) {
            Text(text = "Consultar sensor")
        }
    }
}

@Composable
fun LoadingIndicator() {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        CircularProgressIndicator()
        Text(text = "Cargando...")
    }
}

@Preview(showBackground = true)
@Composable
fun SensorScreenPreview() {
    AC107MurgiTICTheme {
        SensorScreen()
    }
}