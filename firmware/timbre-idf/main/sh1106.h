//
//  sh1106.h
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  Driver de la pantalla OLED SH1106 de 1.3" por I2C.
//
//  En la versión de Arduino esto lo hacía la librería U8g2. ESP-IDF no la
//  trae, así que aquí está lo mínimo que necesita el timbre: un búfer de
//  128x64 píxeles en memoria, cuatro funciones para dibujar encima, y
//  `sh1106_mostrar()` para volcarlo a la pantalla.
//
//  Se dibuja SIEMPRE sobre el búfer y se vuelca una sola vez al final. Así la
//  pantalla no parpadea y el bus I2C se usa una vez por refresco.
//

#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "driver/i2c_master.h"
#include "esp_err.h"

#define SH1106_ANCHO 128
#define SH1106_ALTO 64

// Prepara la pantalla en el bus I2C que ya creó main.c (el mismo del MPU-6050).
esp_err_t sh1106_iniciar(i2c_master_bus_handle_t bus);

// ¿Contestó la pantalla al arrancar? Si no, el resto de funciones no hacen
// nada y el timbre sigue funcionando sin display.
bool sh1106_presente(void);

// Borra el búfer (no la pantalla: eso pasa en el siguiente sh1106_mostrar).
void sh1106_limpiar(void);

void sh1106_pixel(int x, int y, bool encendido);
void sh1106_rect(int x, int y, int ancho, int alto);        // rectángulo relleno
void sh1106_linea(int x0, int y0, int x1, int y1);

// Texto de 5x7 píxeles. (x, y) es la esquina SUPERIOR izquierda.
// Acepta acentos y eñes en UTF-8: se dibujan sin tilde (á → a, ñ → n).
void sh1106_texto(int x, int y, const char *texto);

// El mismo texto al doble de tamaño (10x14), para la hora grande.
void sh1106_texto_grande(int x, int y, const char *texto);

// Ancho en píxeles que ocuparía un texto, para centrarlo.
int sh1106_ancho_texto(const char *texto);

// Vuelca el búfer a la pantalla.
void sh1106_mostrar(void);
