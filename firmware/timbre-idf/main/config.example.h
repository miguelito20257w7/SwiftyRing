//
//  config.example.h
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  Plantilla de configuración. Copiar a `config.h` (en esta misma carpeta) y
//  rellenar con los valores reales. `config.h` NO se sube a git porque lleva
//  la clave del WiFi y la llave del dispositivo; esta plantilla SÍ.
//

#pragma once

// ---- Rol del módulo ----
//
// El sistema tiene DOS módulos con el mismo firmware:
//
//   · el MAESTRO (ROL_ESCLAVO = 0) habla con el servidor, tiene el botón
//     físico y le manda al otro la hora y el horario;
//   · el ESCLAVO (ROL_ESCLAVO = 1) va en el otro edificio, no toca WiFi ni API
//     y no lleva botón: todo le llega por radio (ESP-NOW, ver enlace.c).
//
// No hay que editar esto: el rol se elige al compilar, y cada uno en su propia
// carpeta de compilación para que no se pisen.
//
//   idf.py -B build build flash monitor                     → maestro
//   idf.py -B build-esclavo -DESCLAVO=1 build flash monitor  → esclavo
//
#ifndef ROL_ESCLAVO
#define ROL_ESCLAVO 0
#endif

// Clave compartida por los dos módulos. Va dentro de la firma de cada trama de
// radio, así que sin ella nadie puede mandarle al timbre un "suena ya" ni
// fingir un sismo. Tiene que ser LA MISMA en los dos módulos y distinta de
// esta: cámbiala por algo largo e inventado.
#define ENLACE_CLAVE    "cambia-esta-clave-por-una-larga"

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

#define UART_SISMO_BAUD     115200

// PIN_BOTON solo lo usa el maestro: el esclavo no lleva botón y ese pin se
// queda sin configurar.
#if defined(CONFIG_IDF_TARGET_ESP32S3)

// ESP32-S3 (DevKitC-1)
#define PIN_RELE            4   // relé de estado sólido; se activa en ALTO
#define PIN_BOTON           5   // botón manual (RF-15), contra GND con pull-up
#define PIN_RGB_LED         48  // LED RGB direccionable (WS2812) de la placa ESP32-S3

// Bus I2C 0 (I2C_NUM_0): Pantalla OLED SH1106
#define PIN_I2C_OLED_SDA    8
#define PIN_I2C_OLED_SCL    9
#define I2C_OLED_PORT       I2C_NUM_0

// Bus I2C 1 (I2C_NUM_1): Reloj RTC DS3231 (controlador hardware independiente)
#define PIN_I2C_RTC_SDA     10
#define PIN_I2C_RTC_SCL     11
#define I2C_RTC_PORT        I2C_NUM_1

#define PIN_UART_SISMO_RX   18  // Conectado al TX del coprocesador ESP-01S
#define PIN_UART_SISMO_TX   17
#define UART_SISMO_PORT     UART_NUM_1

#elif defined(CONFIG_IDF_TARGET_ESP32C3)

// ESP32-C3 (Super Mini)
#define PIN_RELE            0   // relé de estado sólido
#define PIN_RELE_UPS        7   // relé de modo UPS (lógica inversa: 0 = encendido, 1 = apagado)
#define PIN_BOTON           1   // botón manual
#define PIN_RGB_LED         2   // tira LED externa (opcional)

// El ESP32-C3 tiene un único bus I2C (I2C_NUM_0).
// Pantalla OLED y Reloj RTC comparten los mismos pines físicos.
#define PIN_I2C_OLED_SDA    8
#define PIN_I2C_OLED_SCL    9
#define I2C_OLED_PORT       I2C_NUM_0

#define PIN_I2C_RTC_SDA     8
#define PIN_I2C_RTC_SCL     9
#define I2C_RTC_PORT        I2C_NUM_0

#define PIN_UART_SISMO_RX   20  // Conectado al TX del coprocesador ESP-01S
#define PIN_UART_SISMO_TX   21
#define UART_SISMO_PORT     UART_NUM_1

#else

// ESP32-WROOM-32 (DevKit)
#define PIN_RELE            26
#define PIN_RELE_UPS        25  // relé de modo UPS (lógica inversa: 0 = encendido, 1 = apagado)
#define PIN_BOTON           27

// Bus I2C 0 (I2C_NUM_0): Pantalla OLED SH1106
#define PIN_I2C_OLED_SDA    21
#define PIN_I2C_OLED_SCL    22
#define I2C_OLED_PORT       I2C_NUM_0

// Bus I2C 1 (I2C_NUM_1): Reloj RTC DS3231 (controlador hardware independiente)
#define PIN_I2C_RTC_SDA     32
#define PIN_I2C_RTC_SCL     33
#define I2C_RTC_PORT        I2C_NUM_1

#define PIN_UART_SISMO_RX   16  // Conectado al TX del coprocesador ESP-01S
#define PIN_UART_SISMO_TX   17
#define UART_SISMO_PORT     UART_NUM_2

#endif

// ---- Zona horaria ----
// Colombia: UTC-5 fijo, sin horario de verano.
#define TZ_COLOMBIA     "<-05>5"
#define NTP_SERVIDOR    "pool.ntp.org"
