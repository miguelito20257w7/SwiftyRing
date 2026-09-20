//
//  timbre.h
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  El relé que suena y el botón físico que lo dispara (RF-15, RF-16).
//

#pragma once

#include <stdbool.h>
#include <stdint.h>

void timbre_iniciar(void);

// Suena el timbre durante `duracion_seg`. `motivo` es lo que aparece en la
// pantalla mientras suena.
void timbre_activar(uint8_t duracion_seg, const char *motivo);

// Se llama en cada vuelta del bucle de control: apaga el relé cuando se cumple
// la duración, atiende el botón físico y ejecuta la orden que haya dejado la
// tarea de red.
void timbre_atender(void);

// Deja una orden para que el bucle de control la ejecute. La usa la tarea de
// red: así el relé lo acciona siempre la misma tarea y no hacen falta candados.
void timbre_pedir_desde_app(uint8_t duracion_seg);

bool timbre_activo(void);
const char *timbre_motivo(void);

// Control del relé de modo UPS (lógica inversa: 0 = activo, 1 = inactivo)
void timbre_fijar_modo_ups(bool activo);
bool timbre_modo_ups(void);

// Duración del timbre al accionar manualmente (botón físico en módulo)
void timbre_fijar_duracion_manual(uint8_t duracion_seg);
uint8_t timbre_duracion_manual(void);

