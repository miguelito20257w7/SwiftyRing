//
//  almacen_config.h
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  Gestión de configuración persistente en NVS (credenciales WiFi, servidor y API Key).
//  Permite la configuración dinámica mediante el Setup Wizard y el restablecimiento
//  de fábrica físico y remoto.
//

#pragma once

#include <stdbool.h>
#include <esp_err.h>

#define MAX_CONFIG_STR 128

typedef struct {
    char wifi_ssid[33];
    char wifi_password[65];
    char api_base[MAX_CONFIG_STR];
    char device_api_key[65];
    char auth_code[33];
} modulo_config_t;

// Inicializa el subsistema de configuración.
esp_err_t almacen_config_iniciar(void);

// Indica si el dispositivo ya fue configurado (existe SSID y clave de API o código en NVS).
bool almacen_config_esta_configurado(void);

// Lee la configuración activa de NVS. Devuelve ESP_OK si se leyó correctamente.
esp_err_t almacen_config_leer(modulo_config_t *cfg);

// Guarda una nueva configuración en NVS.
esp_err_t almacen_config_guardar(const char *ssid, const char *pass, const char *api_base, const char *api_key, const char *auth_code);

// Guarda la clave definitiva asignada por el servidor y borra el código temporal
esp_err_t almacen_config_guardar_device_key(const char *device_key);

// Borra la configuración de NVS y reinicia el dispositivo en modo configuración.
esp_err_t almacen_config_restablecer_fabrica(void);

// Getters en memoria para evitar accesos repetidos a NVS
const char *almacen_config_api_base(void);
const char *almacen_config_device_key(void);
const char *almacen_config_wifi_ssid(void);
const char *almacen_config_wifi_pass(void);
const char *almacen_config_auth_code(void);
bool almacen_config_tiene_auth_code(void);
bool almacen_config_tiene_device_key(void);
