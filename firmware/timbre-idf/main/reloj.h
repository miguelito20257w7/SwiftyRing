//
//  reloj.h
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  La hora del módulo. Se obtiene primero del RTC físico (DS3231) al arrancar,
//  y se mantiene calibrada por NTP o por la hora del servidor en la sincronización.
//

#pragma once

#include <stdbool.h>
#include <time.h>

#include "driver/i2c_master.h"

// Fija la zona horaria de Colombia, inicializa el RTC físico (DS3231)
// y arranca el cliente NTP (en el maestro).
void reloj_iniciar(i2c_master_bus_handle_t bus);

// Deja la hora local en `t`. Devuelve false mientras la hora no sea confiable
// (recién arrancado el ESP32 cree estar en 1970, y con esa hora no se timbra).
bool reloj_hora_local(struct tm *t);

bool reloj_valida(void);

// Pone el reloj con la fecha y hora que mandó el servidor: "2026-08-04" y
// "07:35", y actualiza el RTC físico.
void reloj_fijar_desde_servidor(const char *fecha, const char *hora);

// Pone el reloj con la hora que llegó por el enlace de radio (segundos UTC).
// La usa el esclavo, que no tiene internet ni NTP. Solo mueve el reloj si está
// sin poner o si se ha desviado más de `tolerancia_seg`: el latido del maestro
// llega cada segundo y no tiene sentido reajustarlo cada vez.
void reloj_fijar_epoca(time_t epoca, uint32_t tolerancia_seg);

// Día de la semana como número: 0 = lunes … 5 = sábado. Devuelve -1 el
// domingo, porque el sistema no programa timbres ese día.
int reloj_dia_indice(const struct tm *t);
