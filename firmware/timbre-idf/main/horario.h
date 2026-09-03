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

// ---- El mismo timbre, apretado para que quepa en la radio ----
//
// Por ESP-NOW solo caben 250 bytes por trama, así que al esclavo no se le
// manda el JSON del servidor sino esta versión: sin el UUID (el esclavo no
// reporta a la API, reporta el maestro) y con la etiqueta recortada a lo que
// cabe en la pantalla. 24 bytes en vez de ~80.
typedef struct __attribute__((packed)) {
    uint8_t hora;          // 0..23
    uint8_t minuto;        // 0..59
    uint8_t duracion_seg;
    uint8_t dias;          // la misma máscara de bits de arriba
    char etiqueta[20];     // recortada, siempre terminada en '\0'
} timbre_compacto_t;

// Todo lo del horario que NO son los timbres: los metadatos del especial y la
// calibración del detector de sismos. Viaja en su propia trama, delante de los
// timbres.
typedef struct {
    uint32_t version;       // cambia cuando cambia el horario; así el esclavo sabe si está al día
    uint8_t cant_habitual;
    uint8_t cant_especial;
    bool hay_especial;
    char especial_nombre[33];
    char especial_inicio[11];  // "2026-08-03"
    char especial_fin[11];
    float umbral_sismico_g;
    uint16_t sismo_duracion_min_ms;
} horario_resumen_t;

// Cuántos timbres hay en total contando el especial: es el tope de lo que
// puede viajar por el enlace.
#define MAX_TIMBRES_TOTAL (MAX_TIMBRES * 2)

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

// ---- Lo que usa el enlace entre los dos módulos ----

// Huella del horario que hay cargado ahora mismo. El maestro la manda en cada
// latido; si no coincide con la del esclavo, le empuja el horario nuevo.
uint32_t horario_version(void);

// Los metadatos del horario cargado, para mandárselos al esclavo.
void horario_resumen(horario_resumen_t *salida);

// Copia hasta `max` timbres en formato compacto, empezando por el número
// `desde`. Se numeran seguidos: primero los habituales y detrás los del
// especial. Devuelve cuántos copió (0 = ya no quedan).
uint8_t horario_exportar(uint16_t desde, timbre_compacto_t *destino, uint8_t max);

// Reemplaza el horario con el que llegó por el enlace y lo guarda en la flash
// del esclavo, para que siga timbrando si el maestro se apaga (RF-31).
void horario_aplicar_binario(const horario_resumen_t *resumen, const timbre_compacto_t *timbres,
                             uint16_t cantidad);
