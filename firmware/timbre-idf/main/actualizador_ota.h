//
//  actualizador_ota.h
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  Descarga y aplicación de actualizaciones de firmware por HTTPS con
//  mecanismo de rollback automático si el nuevo arranque falla.
//

#pragma once

#include <stdbool.h>
#include <esp_err.h>

// Inicia la descarga y flasheo de una actualización desde una URL HTTPS
esp_err_t actualizador_ota_iniciar(const char *url_binario);

// Confirma que el arranque actual es válido y cancela el rollback automático
void actualizador_ota_confirmar_arranque(void);

// Indica si hay un proceso de actualización OTA en curso
bool actualizador_ota_en_curso(void);
