//
//  reloj.h
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  La hora del módulo. Se pone en hora por NTP; si la red del colegio bloquea
//  el NTP, el servidor manda su propia hora en la sincronización del horario.
//

#pragma once

#include <stdbool.h>
#include <time.h>

// Fija la zona horaria de Colombia y arranca el cliente NTP.
void reloj_iniciar(void);

// Deja la hora local en `t`. Devuelve false mientras la hora no sea confiable
// (recién arrancado el ESP32 cree estar en 1970, y con esa hora no se timbra).
bool reloj_hora_local(struct tm *t);

bool reloj_valida(void);

// Pone el reloj con la fecha y hora que mandó el servidor: "2026-08-04" y
// "07:35".
void reloj_fijar_desde_servidor(const char *fecha, const char *hora);

// Día de la semana como número: 0 = lunes … 5 = sábado. Devuelve -1 el
// domingo, porque el sistema no programa timbres ese día.
int reloj_dia_indice(const struct tm *t);
