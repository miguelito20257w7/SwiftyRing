//
//  rtc.h
//  SwiftyRing · Firmware del módulo de timbre (ESP-IDF)
//
//  Controlador del reloj en tiempo real físico (RTC DS3231) por I2C.
//  Permite al módulo conocer la hora exacta inmediatamente al encender,
//  incluso tras un corte de energía y sin conexión a internet.
//

#pragma once

#include <stdbool.h>
#include <time.h>

#include "driver/i2c_master.h"
#include "esp_err.h"

// Inicializa el dispositivo I2C del DS3231 en el bus I2C maestro compartido.
esp_err_t rtc_iniciar(i2c_master_bus_handle_t bus);

// Devuelve true si el RTC respondió por el bus I2C.
bool rtc_presente(void);

// Devuelve true si el RTC tiene una hora válida (año >= 2026 y oscilador sin paro).
bool rtc_hora_valida(void);

// Lee la hora del RTC y, si es válida, la aplica al reloj del sistema mediante settimeofday().
// Devuelve true si la hora del sistema fue fijada con éxito.
bool rtc_leer_y_fijar_sistema(void);

// Toma la hora actual del sistema (obtenida por NTP o por el backend Vapor)
// y la escribe en el DS3231, limpiando la bandera de paro del oscilador.
bool rtc_actualizar_desde_sistema(void);

// Devuelve la temperatura interna del DS3231 en grados Celsius (resolución 0.25 °C),
// o -100.0f si el RTC no está disponible.
float rtc_temperatura(void);
