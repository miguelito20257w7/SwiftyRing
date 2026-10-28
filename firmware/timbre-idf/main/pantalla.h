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

// La pantalla normal de operación.
void pantalla_dibujar(void);

// Notifica un cambio recibido del servidor o app (ej. Modo UPS, duración, horario).
// Muestra una tarjeta temporal emergente durante 3 segundos.
void pantalla_notificar_cambio(const char *titulo, const char *detalle);
bool pantalla_tiene_aviso(void);

// Muestra la pantalla de cuenta regresiva para el restablecimiento de fábrica.
void pantalla_cuenta_regresiva_reset(int segundos_restantes);

// Limpia el estado de cuenta regresiva cuando se suelta el botón antes de tiempo.
void pantalla_cancelar_cuenta_regresiva(void);
