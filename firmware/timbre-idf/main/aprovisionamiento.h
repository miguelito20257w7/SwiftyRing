//
//  aprovisionamiento.h
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  Modo de configuración asistida (SoftAP + Servidor HTTP local).
//  Permite al Setup Wizard de la app Flutter aprovisionar la red escolar.
//

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <esp_err.h>

// Inicia el SoftAP (SwiftyRing-XXXX) y el servidor HTTP local en 192.168.4.1
esp_err_t aprovisionamiento_iniciar(void);

// Detiene el SoftAP y el servidor HTTP
void aprovisionamiento_detener(void);

// Indica si el modo de aprovisionamiento está activo actualmente
bool aprovisionamiento_activo(void);

// Obtiene el nombre del SoftAP generado (ej. "SwiftyRing-A1B2")
void aprovisionamiento_obtener_ssid_ap(char *buf, size_t max_len);
