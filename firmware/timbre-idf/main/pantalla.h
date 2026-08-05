//
//  pantalla.h
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  Lo que se ve en la OLED: hora, próximo timbre, cuenta atrás, aviso de
//  timbre sonando y de "sin conexión" (RF-24 a RF-27).
//

#pragma once

#include "driver/i2c_master.h"

void pantalla_iniciar(i2c_master_bus_handle_t bus);

// Dos líneas sueltas, para los mensajes del arranque.
void pantalla_mensaje(const char *linea1, const char *linea2);

// La pantalla normal de operación. Se redibuja cuatro veces por segundo.
void pantalla_dibujar(void);
