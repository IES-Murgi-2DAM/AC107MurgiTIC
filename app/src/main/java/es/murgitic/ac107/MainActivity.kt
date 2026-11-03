package es.murgitic.ac107

import android.os.Bundle
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import es.murgitic.ac107.ui.theme.AC107MurgiTICTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.time.Duration.Companion.milliseconds

val temps = listOf(22.5, 23.0, 21.8, 24.2, 22.9)
val humids = listOf(60, 55, 65, 70, 58)

val sensorReadings =
    temps.mapIndexed { index, temp -> LecturaSensor("Sensor ${index + 1}", TipoSensor.TEMPERATURA, temp) }
        .plus(humids.mapIndexed { index, humid ->
            LecturaSensor(
                "Sensor ${index + 1}",
                TipoSensor.HUMEDAD,
                humid.toDouble()
            )
        })

fun getRandomSensorReading(): String {
    val lectura : LecturaSensor = sensorReadings.random()
    return when (lectura.tipo) {
        TipoSensor.TEMPERATURA -> "Lectura Sensor 1: ${lectura.valor}ºC"
        TipoSensor.HUMEDAD -> "Lectura Sensor 2: ${lectura.valor}% humedad"
    }
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
    val corrutina = rememberCoroutineScope()

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
                corrutina.launch {
                    isLoading.value = true
                    delay(2000.milliseconds) // Simulamos un retraso de 2 segundos para la consulta del sensor
                    actualReading.value = getRandomSensorReading()
                    isLoading.value = false
                }
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