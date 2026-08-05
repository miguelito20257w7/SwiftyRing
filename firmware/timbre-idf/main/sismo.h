//
//  sismo.h
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  Detección de sismos con el acelerómetro MPU-6050 (RF-18, RF-19, RF-22).
//

#pragma once

#include "driver/i2c_master.h"
#include "esp_err.h"

// Despierta el sensor en el bus I2C que comparte con la pantalla.
esp_err_t sismo_iniciar(i2c_master_bus_handle_t bus);

// Una muestra del acelerómetro. Se llama 50 veces por segundo desde el bucle
// de control; si el episodio de vibración resulta ser un sismo, hace sonar la
// alarma por su cuenta.
void sismo_muestrear(void);
