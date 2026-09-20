//
//  canal.h
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  Canal WebSocket persistente con el backend. Reemplaza el polling de
//  comandos: en vez de preguntar cada 2 s si hay orden, el servidor la empuja
//  al instante. Los cambios de horario y configuración también se avisan por
//  aquí, y el módulo reacciona pidiendo la sincronización completa por HTTP.
//
//  Solo lo usa el MAESTRO. El esclavo recibe todo del maestro por ESP-NOW.
//

#pragma once

#include <stdbool.h>

// Abre el WebSocket al servidor. Se llama una vez, después de red_iniciar().
void canal_iniciar(void);

// Se llama en cada vuelta del bucle de control: procesa los mensajes que
// llegaron por el WebSocket y los despacha (timbrar, sincronizar...).
void canal_atender(void);

// ¿El WebSocket está conectado ahora mismo?
bool canal_conectado(void);
