//
//  config.example.h
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  Plantilla de configuración. Copiar a `config.h` (en esta misma carpeta) y
//  rellenar con los valores reales. `config.h` NO se sube a git porque lleva
//  la clave del WiFi y la llave del dispositivo; esta plantilla SÍ.
//

#pragma once

// ---- Red ----
#define WIFI_SSID       "NOMBRE_DE_LA_RED"
#define WIFI_PASSWORD   "CLAVE_DE_LA_RED"

// URL base de la API, SIN barra final.
//
// Tiene que ser https: el servidor redirige todo el tráfico a HTTPS, y además
// la DEVICE_API_KEY de abajo viaja en una cabecera de cada petición. En texto
// plano, cualquiera en la red del colegio podría leerla y hacer sonar el
// timbre cuando quisiera.
//
// Para probar contra el Vapor de tu computador, va la IP de la máquina (no
// "localhost": eso sería el propio ESP32), así:
//   #define API_BASE "http://192.168.1.100:8080/api"
#define API_BASE        "https://swiftyring.swiftydevs.dev/api"

// La misma llave que DEVICE_API_KEY en el .env del backend.
#define DEVICE_API_KEY  "dev-esp32-timbre-2026"

// ---- Pines ----
//
// El firmware sirve para dos placas y cada una tiene sus pines. No hay que
// tocar nada: el chip para el que se está compilando lo dice `sdkconfig.h`,
// que lo genera `idf.py set-target`.
//
// Por qué no valen los mismos en las dos: en el ESP32-S3 los GPIO 26 y 27
// están cableados a la memoria flash interna del módulo, y el GPIO 22 ni
// siquiera existe (la numeración salta del 21 al 26).
#include "sdkconfig.h"

#if defined(CONFIG_IDF_TARGET_ESP32S3)

// ESP32-S3 (DevKitC-1)
#define PIN_RELE        4   // relé de estado sólido; se activa en ALTO
#define PIN_BOTON       5   // botón manual (RF-15), contra GND con pull-up
#define PIN_I2C_SDA     8   // bus de la pantalla SH1106 y el MPU-6050
#define PIN_I2C_SCL     9
#define PIN_RGB_LED     48  // LED RGB direccionable (WS2812) de la placa ESP32-S3

#else

// ESP32-WROOM-32 (DevKit)
#define PIN_RELE        26
#define PIN_BOTON       27
#define PIN_I2C_SDA     21
#define PIN_I2C_SCL     22

#endif

// ---- Zona horaria ----
// Colombia: UTC-5 fijo, sin horario de verano.
#define TZ_COLOMBIA     "<-05>5"
#define NTP_SERVIDOR    "pool.ntp.org"
