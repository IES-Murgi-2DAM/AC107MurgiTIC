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
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(text = "Sensor MurgiTIC")
        // Asigno al texto que muestra el estado el valor actual de la variable actualReading, que se actualizará cada vez que se pulse el botón
        Text(text = actualReading.value)
        // En la lambda del onClick del botón, actualizo el valor de la variable actualReading con el valor devuelto por la función getRandomSensorReading
        Button(onClick = { actualReading.value = getRandomSensorReading() }) {
            Text(text = "Consultar sensor")
        }
    }
}

@Preview(showBackground = true)
@Composable
fun SensorScreenPreview() {
    AC107MurgiTICTheme {
        SensorScreen()
    }
}