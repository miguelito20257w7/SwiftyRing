//
//  red.h
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  Todo lo que habla con el backend Vapor: WiFi, sincronización del horario,
//  órdenes de la app y la cola de reportes que sobrevive a los cortes de
//  internet (RF-17, RF-28, RF-30, RNF-04).
//
//  Esto es cosa del MAESTRO. En el esclavo (ROL_ESCLAVO = 1) nada de aquí se
//  arranca y las funciones de encolar no hacen nada: el esclavo no habla con el
//  servidor, habla con el maestro por enlace.c y es el maestro quien reporta.
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

// `confirmado_por_nodo2` dice si el otro módulo también sintió la sacudida, y
// `intensidad_nodo2_g` con cuánta fuerza. Va a la bitácora para poder revisar
// después por qué sonó (o por qué no) una alarma.
void red_encolar_sismo(float intensidad_g, uint32_t duracion_ms, bool confirmado_por_nodo2,
                       float intensidad_nodo2_g);

// El WebSocket avisó que hay horario nuevo: sincronizar en el acto.
void red_pedir_sincronizacion(void);
void red_pedir_sincronizacion_motivo(const char *motivo);
uint32_t red_tiempo_desde_sync(void);
