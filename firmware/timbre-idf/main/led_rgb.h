//
//  led_rgb.h
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  Control del LED RGB direccionable (WS2812) integrado en la placa ESP32-S3.
//

#pragma once

#include <stdbool.h>

// Inicializa el dispositivo de la tira/LED RGB en el GPIO configurado.
void led_rgb_iniciar(void);

// Atiende el estado del LED RGB en cada ciclo.
// Si `timbre_activo` es true, hace titilar el LED en un patrón estroboscópico de alto impacto.
// Si es false, apaga el LED por completo.
void led_rgb_atender(bool timbre_activo);
