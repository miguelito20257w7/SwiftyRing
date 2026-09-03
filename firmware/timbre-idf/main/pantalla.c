//
//  pantalla.c
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  Dashboard Científico STA/LTA y Procesamiento Sísmico MPU-6050
//

#include "pantalla.h"

#include <stdio.h>
#include <string.h>

#include "config.h"
#include "enlace.h"
#include "horario.h"
#include "red.h"
#include "reloj.h"
#include "rtc.h"
#include "sh1106.h"
#include "sismo.h"
#include "timbre.h"

void pantalla_iniciar(i2c_master_bus_handle_t bus) { sh1106_iniciar(bus); }

void pantalla_mensaje(const char *linea1, const char *linea2) {
    sh1106_limpiar();
    sh1106_texto_grande(2, 12, linea1);
    sh1106_texto(2, 40, linea2);
    sh1106_mostrar();
}

void pantalla_dibujar(void) {
    if (!sh1106_presente()) return;

    sh1106_limpiar();

    char linea[32];
    int estado = sismo_estado();
    bool alarma = timbre_activo() || (estado == 2);

    // ============================================================
    // 1. ENCABEZADO DE ESTADO (Y = 0)
    // ============================================================
    if (alarma) {
        sh1106_texto(10, 0, "¡¡ ALARMA SISMO ACTIVA !!");
    } else if (estado == 1) {
        sh1106_texto(6, 0, ">> PRE-TRIGGER STA/LTA <<");
    } else {
        sh1106_texto(12, 0, "= SISMOMETRO STA/LTA =");
    }

    sh1106_linea(0, 9, 127, 9);

    // ============================================================
    // 2. COCIENTE STA/LTA (Y = 11)
    // ============================================================
    float ratio = sismo_ratio_actual();
    snprintf(linea, sizeof(linea), "STA/LTA: %4.1f (Trig:4.5)", ratio);
    sh1106_texto(0, 11, linea);

    // ============================================================
    // 3. PGA DINÁMICO (0.5 - 10.0 Hz) (Y = 20)
    // ============================================================
    float pga = sismo_dynamic_magnitude();
    float min_pga = horario_umbral_sismico();
    snprintf(linea, sizeof(linea), "PGA: %.3fg  (Min:%.2fg)", pga, min_pga);
    sh1106_texto(0, 20, linea);

    // ============================================================
    // 4. VÚMETRO DEL RATIO STA/LTA (Y = 29 a 35)
    // ============================================================
    // Marco exterior (120 px de ancho, escala de 0.0 a 10.0 de Ratio)
    sh1106_linea(4, 29, 124, 29);
    sh1106_linea(4, 35, 124, 35);
    sh1106_linea(4, 29, 4, 35);
    sh1106_linea(124, 29, 124, 35);

    // Relleno proporcional al ratio STA/LTA
    int relleno_w = (int)((ratio / 10.0f) * 118);
    if (relleno_w > 118) relleno_w = 118;
    if (relleno_w > 0) {
        sh1106_rect(5, 30, relleno_w, 5);
    }

    // Muesca vertical en el umbral de disparo Alfa = 4.5
    int muesca_x = 5 + (int)((4.5f / 10.0f) * 118);
    sh1106_linea(muesca_x, 28, muesca_x, 36);

    // ============================================================
    // 5. TIEMPO SOSTENIDO Y PROGRESO (Y = 38)
    // ============================================================
    int muestras = sismo_contador_muestras();
    int requeridas = sismo_muestras_requeridas();
    int pct = requeridas > 0 ? (muestras * 100) / requeridas : 0;
    if (pct > 100) pct = 100;
    snprintf(linea, sizeof(linea), "T: %dms / %dms (%d%%)",
             muestras * 10, requeridas * 10, pct);
    sh1106_texto(0, 38, linea);

    // ============================================================
    // 6. TASA CAV (Velocidad Absoluta Acumulada) (Y = 47)
    // ============================================================
    float cav_rate = sismo_cav_rate();
    snprintf(linea, sizeof(linea), "CAV: %.3f g*s/s (>=.02)", cav_rate);
    sh1106_texto(0, 47, linea);

    // ============================================================
    // 7. MODO Y ENLACE UART (Y = 56)
    // ============================================================
    bool uart_ok = sismo_coprocesador_conectado();
    bool pareja = enlace_pareja_viva();
    if (alarma) {
        snprintf(linea, sizeof(linea), "RELE ACTIVADO (30s)");
    } else {
        snprintf(linea, sizeof(linea), "UART:%s | %s",
                 uart_ok ? "100Hz" : "NO",
                 pareja ? "Pareja" : "Solo");
    }
    sh1106_texto(0, 56, linea);

    sh1106_mostrar();
}
