//
//  sh1106.c
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//

#include "sh1106.h"

#include <string.h>

#include "esp_log.h"
#include "fuente5x7.h"

static const char *TAG = "pantalla";

#define SH1106_DIRECCION 0x3C
#define SH1106_PAGINAS (SH1106_ALTO / 8)
// El SH1106 tiene 132 columnas de memoria pero solo 128 se ven: la primera
// columna visible es la 2. Sin este desfase el dibujo sale corrido.
#define SH1106_DESFASE_COLUMNA 2

static i2c_master_dev_handle_t s_pantalla = NULL;
static bool s_presente = false;

// El búfer: una fila de bytes por cada "página" de 8 píxeles de alto.
// El píxel (x, y) es el bit (y % 8) del byte s_buf[y / 8][x].
static uint8_t s_buf[SH1106_PAGINAS][SH1106_ANCHO];

// ============================================================
// Conversación con el chip
// ============================================================

// Cada envío I2C empieza por un byte que dice qué viene: 0x00 = orden,
// 0x40 = píxeles.
static esp_err_t enviar_comando(uint8_t comando) {
    uint8_t marco[2] = {0x00, comando};
    return i2c_master_transmit(s_pantalla, marco, sizeof(marco), 100);
}

static esp_err_t enviar_pagina(const uint8_t *pixeles) {
    uint8_t marco[1 + SH1106_ANCHO];
    marco[0] = 0x40;
    memcpy(marco + 1, pixeles, SH1106_ANCHO);
    return i2c_master_transmit(s_pantalla, marco, sizeof(marco), 100);
}

esp_err_t sh1106_iniciar(i2c_master_bus_handle_t bus) {
    i2c_device_config_t cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = SH1106_DIRECCION,
        .scl_speed_hz = 400000,
    };
    esp_err_t err = i2c_master_bus_add_device(bus, &cfg, &s_pantalla);
    if (err != ESP_OK) return err;

    // Secuencia de arranque del SH1106. Los pares son orden + valor.
    static const uint8_t arranque[] = {
        0xAE,        // pantalla apagada mientras se configura
        0xD5, 0x80,  // frecuencia del reloj interno
        0xA8, 0x3F,  // 64 filas
        0xD3, 0x00,  // sin desplazamiento vertical
        0x40,        // empezar a dibujar en la fila 0
        0xAD, 0x8B,  // convertidor de voltaje interno encendido
        0x32,        // nivel de la bomba de carga (8.0 V)
        0xA1,        // columnas de izquierda a derecha
        0xC8,        // filas de arriba abajo
        0xDA, 0x12,  // cableado de las filas en este panel
        0x81, 0x80,  // brillo
        0xD9, 0x22,  // tiempo de precarga
        0xDB, 0x35,  // nivel de referencia
        0xA4,        // mostrar lo que hay en memoria
        0xA6,        // sin invertir el blanco y el negro
        0xAF,        // pantalla encendida
    };
    for (size_t i = 0; i < sizeof(arranque); i++) {
        if (enviar_comando(arranque[i]) != ESP_OK) {
            ESP_LOGW(TAG, "la pantalla no responde; el timbre sigue sin ella");
            return ESP_FAIL;
        }
    }

    s_presente = true;
    sh1106_limpiar();
    sh1106_mostrar();
    ESP_LOGI(TAG, "SH1106 lista");
    return ESP_OK;
}

bool sh1106_presente(void) { return s_presente; }

void sh1106_mostrar(void) {
    if (!s_presente) return;
    for (int pagina = 0; pagina < SH1106_PAGINAS; pagina++) {
        enviar_comando(0xB0 + pagina);
        enviar_comando(0x00 | (SH1106_DESFASE_COLUMNA & 0x0F));
        enviar_comando(0x10 | (SH1106_DESFASE_COLUMNA >> 4));
        enviar_pagina(s_buf[pagina]);
    }
}

// ============================================================
// Dibujo sobre el búfer
// ============================================================

void sh1106_limpiar(void) { memset(s_buf, 0, sizeof(s_buf)); }

void sh1106_pixel(int x, int y, bool encendido) {
    if (x < 0 || x >= SH1106_ANCHO || y < 0 || y >= SH1106_ALTO) return;
    uint8_t mascara = 1 << (y % 8);
    if (encendido) {
        s_buf[y / 8][x] |= mascara;
    } else {
        s_buf[y / 8][x] &= ~mascara;
    }
}

void sh1106_rect(int x, int y, int ancho, int alto) {
    for (int j = 0; j < alto; j++) {
        for (int i = 0; i < ancho; i++) sh1106_pixel(x + i, y + j, true);
    }
}

// Algoritmo de Bresenham: avanza siempre un píxel en la dirección larga y de
// vez en cuando uno en la corta, sin usar decimales.
void sh1106_linea(int x0, int y0, int x1, int y1) {
    int dx = x1 > x0 ? x1 - x0 : x0 - x1;
    int dy = y1 > y0 ? y1 - y0 : y0 - y1;
    int pasoX = x0 < x1 ? 1 : -1;
    int pasoY = y0 < y1 ? 1 : -1;
    int error = dx - dy;

    while (true) {
        sh1106_pixel(x0, y0, true);
        if (x0 == x1 && y0 == y1) break;
        int error2 = error * 2;
        if (error2 > -dy) {
            error -= dy;
            x0 += pasoX;
        }
        if (error2 < dx) {
            error += dx;
            y0 += pasoY;
        }
    }
}

// ============================================================
// Texto
// ============================================================

// Devuelve la posición del carácter dentro de la tabla de la fuente y avanza
// el puntero. Los caracteres acentuados ocupan dos bytes en UTF-8 ("á" es
// C3 A1): se leen los dos y se dibuja la letra sin tilde, porque la fuente
// solo tiene los 95 caracteres del teclado inglés.
static int siguiente_glifo(const char **texto) {
    unsigned char c = (unsigned char)*(*texto)++;

    if (c < 0x80) {
        if (c < 0x20 || c > 0x7E) return '?' - 0x20;
        return c - 0x20;
    }

    unsigned char segundo = (unsigned char)**texto;
    if (segundo != '\0') (*texto)++;

    char base = '?';
    if (c == 0xC3) {
        switch (segundo) {
            case 0xA0: case 0xA1: case 0xA2: case 0xA4: base = 'a'; break;
            case 0x80: case 0x81: case 0x82: case 0x84: base = 'A'; break;
            case 0xA8: case 0xA9: case 0xAA: case 0xAB: base = 'e'; break;
            case 0x88: case 0x89: case 0x8A: case 0x8B: base = 'E'; break;
            case 0xAC: case 0xAD: case 0xAE: case 0xAF: base = 'i'; break;
            case 0x8C: case 0x8D: case 0x8E: case 0x8F: base = 'I'; break;
            case 0xB2: case 0xB3: case 0xB4: case 0xB6: base = 'o'; break;
            case 0x92: case 0x93: case 0x94: case 0x96: base = 'O'; break;
            case 0xB9: case 0xBA: case 0xBB: case 0xBC: base = 'u'; break;
            case 0x99: case 0x9A: case 0x9B: case 0x9C: base = 'U'; break;
            case 0xB1: base = 'n'; break;
            case 0x91: base = 'N'; break;
            case 0xA7: base = 'c'; break;
            case 0x87: base = 'C'; break;
        }
    } else if (c == 0xC2) {
        if (segundo == 0xA1) base = '!';        // ¡
        else if (segundo == 0xBF) base = '?';   // ¿
        else if (segundo == 0xB0) base = 'o';   // grados
        else base = ' ';
    }
    return base - 0x20;
}

static void dibujar_glifo(int x, int y, int indice, int escala) {
    for (int columna = 0; columna < FUENTE_ANCHO; columna++) {
        uint8_t bits = FUENTE_5X7[indice][columna];
        for (int fila = 0; fila < FUENTE_ALTO; fila++) {
            if ((bits & (1 << fila)) == 0) continue;
            if (escala == 1) {
                sh1106_pixel(x + columna, y + fila, true);
            } else {
                // Cada píxel de la fuente pasa a ser un cuadrado de escala×escala.
                sh1106_rect(x + columna * escala, y + fila * escala, escala, escala);
            }
        }
    }
}

static void escribir(int x, int y, const char *texto, int escala) {
    if (!s_presente) return;
    while (*texto != '\0') {
        int indice = siguiente_glifo(&texto);
        dibujar_glifo(x, y, indice, escala);
        x += FUENTE_AVANCE * escala;
        if (x >= SH1106_ANCHO) return;  // lo que no cabe, no se dibuja
    }
}

void sh1106_texto(int x, int y, const char *texto) { escribir(x, y, texto, 1); }

void sh1106_texto_grande(int x, int y, const char *texto) { escribir(x, y, texto, 2); }

int sh1106_ancho_texto(const char *texto) {
    int caracteres = 0;
    while (*texto != '\0') {
        siguiente_glifo(&texto);
        caracteres++;
    }
    return caracteres * FUENTE_AVANCE;
}
