//
//  config.example.h
//  SwiftyRing · firmware del módulo de timbre
//
//  Plantilla de configuración. Copiar a `config.h` (en esta misma carpeta) y
//  rellenar con los valores reales. `config.h` NO se sube a git porque lleva
//  la clave del WiFi y la llave del dispositivo; esta plantilla SÍ.
//

#pragma once

// ---- Red ----
#define WIFI_SSID       "NOMBRE_DE_LA_RED"
#define WIFI_PASSWORD   "CLAVE_DE_LA_RED"

// URL base de la API, SIN barra final. En desarrollo es la IP del computador
// donde corre Vapor (no "localhost": eso sería el propio ESP32).
#define API_BASE        "http://192.168.1.100:8080/api"

// La misma llave que DEVICE_API_KEY en el .env del backend.
#define DEVICE_API_KEY  "dev-esp32-timbre-2026"

// ---- Pines (ESP32 DevKit / WROOM-32) ----
// Relé de estado sólido que acciona el timbre. Se activa en ALTO.
#define PIN_RELE        26

// Botón físico de timbre manual (RF-15), contra GND con pull-up interno.
#define PIN_BOTON       27

// Bus I2C compartido por la pantalla OLED SH1106 y el acelerómetro MPU-6050.
#define PIN_I2C_SDA     21
#define PIN_I2C_SCL     22

// LED RGB direccionable WS2812 en ESP32-S3 (GPIO 48)
#define PIN_RGB_LED     48

// ---- Zona horaria ----
// Colombia: UTC-5 fijo, sin horario de verano.
#define TZ_COLOMBIA     "<-05>5"
#define NTP_SERVIDOR    "pool.ntp.org"
