//
//  red.h
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  Todo lo que habla con el backend Vapor: WiFi, sincronización del horario,
//  órdenes de la app y la cola de reportes que sobrevive a los cortes de
//  internet (RF-17, RF-28, RF-30, RNF-04).
//

#pragma once

#include <stdbool.h>
#include <stdint.h>

// Arranca el WiFi y prepara la cola de reportes.
void red_iniciar(void);

bool red_en_linea(void);

// Tarea de FreeRTOS con todo el trabajo de red. Corre aparte del bucle de
// control para que una consulta HTTP lenta no atrase un timbre.
void red_tarea(void *argumento);

// Reportes para la bitácora. Se guardan primero en la flash y se envían
// cuando hay conexión, así que se pueden llamar sin red.
void red_encolar_activacion(const char *tipo, const char *timbre_id, int duracion_seg);
void red_encolar_sismo(float intensidad_g, uint32_t duracion_ms);
