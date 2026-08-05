//
//  comun.h
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  Lo poquito que usan todos los módulos.
//

#pragma once

#include <stdint.h>

#include "esp_timer.h"

// Milisegundos desde que arrancó el módulo, igual que el millis() de Arduino.
// ESP-IDF cuenta en microsegundos, así que se dividen entre mil.
static inline uint32_t millis(void) { return (uint32_t)(esp_timer_get_time() / 1000); }

// Carpeta donde se monta la memoria flash de datos (horario y cola de reportes).
#define RUTA_ALMACEN "/almacen"
