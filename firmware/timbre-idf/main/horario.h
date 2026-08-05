//
//  horario.h
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  El horario que el módulo guarda en su memoria flash y con el que decide
//  qué suena y cuándo (RF-07, RF-28, RF-31).
//

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <time.h>

#define MAX_TIMBRES 32

// Un timbre programado, tal como llega de /api/dispositivo/horario.
typedef struct {
    char id[37];        // UUID, para reportar qué timbre sonó
    char etiqueta[33];  // "Inicio de clases"
    char hora[6];       // "07:00" (siempre con cero a la izquierda)
    uint8_t duracion_seg;
    uint8_t dias;       // Máscara de bits: bit 0 = lunes … bit 5 = sábado
} timbre_programado_t;

// Monta lo que haya guardado en la flash. Se llama ANTES de tocar la red: si
// el colegio amaneció sin internet, el primer timbre suena igual (RF-31).
void horario_iniciar(void);

// Reemplaza el horario en memoria con el del JSON. Si `recien_del_servidor`
// es true, además lo guarda en la flash y aprovecha la hora que viene dentro.
bool horario_aplicar_json(const char *json, bool recien_del_servidor);

// Se llama en cada vuelta del bucle de control: si acaba de empezar un minuto
// nuevo, hace sonar los timbres que caen en él.
void horario_revisar(void);

// El próximo toque de hoy, para la pantalla (RF-25). false si ya no queda
// ninguno.
bool horario_proximo(const struct tm *t, timbre_programado_t *salida);

// ¿Manda hoy un horario especial? (RF-10..12)
bool horario_especial_vigente(const struct tm *t);
void horario_especial_nombre(char *destino, size_t tam);

// Calibración del detector de sismos que baja del servidor (RF-19).
float horario_umbral_sismico(void);
int horario_sismo_duracion_min_ms(void);
