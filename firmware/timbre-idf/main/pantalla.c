//
//  pantalla.c
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  Dashboard limpio y simplificado para el timbre escolar (OLED SH1106 128x64):
//  - Zona superior: Hora grande con insignia de conectividad.
//  - Zona media: Próximo timbre y cuenta regresiva con buen espaciado.
//  - Zona inferior: Barra de estado unificada (Temperatura/RTC, MPU, Red).
//

#include "pantalla.h"

#include <stdio.h>
#include <string.h>

#include "comun.h"
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

static bool hay_conexion(void) {
#if ROL_ESCLAVO
    return enlace_pareja_viva();
#else
    return red_en_linea();
#endif
}

static char s_aviso_titulo[24] = "";
static char s_aviso_detalle[32] = "";
static uint32_t s_aviso_hasta = 0;
static int s_ultimo_minuto_prox = -1;
static timbre_programado_t s_proximo_cache;
static bool s_hay_proximo_cache = false;
static bool s_especial_vigente_cache = false;
static char s_especial_nombre_cache[25] = "";

void pantalla_notificar_cambio(const char *titulo, const char *detalle) {
    strlcpy(s_aviso_titulo, titulo ? titulo : "", sizeof(s_aviso_titulo));
    strlcpy(s_aviso_detalle, detalle ? detalle : "", sizeof(s_aviso_detalle));
    s_aviso_hasta = millis() + 3000;
    s_ultimo_minuto_prox = -1;
    pantalla_dibujar();
}

bool pantalla_tiene_aviso(void) {
    return millis() < s_aviso_hasta;
}

void pantalla_mensaje(const char *linea1, const char *linea2) {
    sh1106_limpiar();
    sh1106_texto_grande(2, 12, linea1);
    sh1106_texto(2, 40, linea2);
    sh1106_mostrar();
}

void pantalla_dibujar(void) {
    if (!sh1106_presente()) return;

    // ============================================================
    // 0. AVISO VISUAL DE CAMBIO (Popup temporal de 3 segundos)
    // ============================================================
    if (millis() < s_aviso_hasta && !timbre_activo()) {
        sh1106_limpiar();
        // Borde exterior del popup
        sh1106_linea(0, 0, 127, 0);
        sh1106_linea(0, 63, 127, 63);
        sh1106_linea(0, 0, 0, 63);
        sh1106_linea(127, 0, 127, 63);
        sh1106_linea(0, 16, 127, 16);

        // Encabezado centrado
        const char *hdr = "[ CAMBIO APLICADO ]";
        int ancho_hdr = sh1106_ancho_texto(hdr);
        int x_hdr = (128 - ancho_hdr) / 2;
        if (x_hdr < 2) x_hdr = 2;
        sh1106_texto(x_hdr, 4, hdr);

        // Título en texto grande centrado
        int ancho_tit = sh1106_ancho_texto(s_aviso_titulo) * 2;
        int x_tit = (128 - ancho_tit) / 2;
        if (x_tit < 4) x_tit = 4;
        sh1106_texto_grande(x_tit, 22, s_aviso_titulo);

        // Detalle en texto normal centrado
        int ancho_det = sh1106_ancho_texto(s_aviso_detalle);
        int x_det = (128 - ancho_det) / 2;
        if (x_det < 4) x_det = 4;
        sh1106_texto(x_det, 46, s_aviso_detalle);

        sh1106_mostrar();
        return;
    }

    // ============================================================
    // 1. MODO ALERTA COMPLETA (Timbre sonando o Alarma Sísmica)
    // ============================================================
    if (timbre_activo()) {
        sh1106_limpiar();
        if (strcmp(timbre_motivo(), "SISMO") == 0) {
            sh1106_texto_grande(16, 12, "¡ALERTA!");
            sh1106_texto_grande(20, 36, "¡SISMO!");
        } else {
            sh1106_texto_grande(16, 14, "¡TIMBRE!");
            sh1106_texto(16, 42, timbre_motivo());
        }
        sh1106_mostrar();
        return;
    }

    sh1106_limpiar();

    struct tm t;
    bool hora_ok = reloj_hora_local(&t);

    // ============================================================
    // 2. PANTALLA DE ESPERA (Si aún no hay hora válida)
    // ============================================================
    if (!hora_ok) {
        sh1106_texto_grande(2, 4, "Sin hora");
        sh1106_linea(0, 22, 127, 22);

        char linea[32];
        snprintf(linea, sizeof(linea), "RTC: %s",
                 rtc_presente() ? (rtc_hora_valida() ? "OK" : "Sin pila/hora") : "No detectado");
        sh1106_texto(2, 28, linea);

        sh1106_texto(2, 40, red_en_linea() ? "WiFi: Conectado" : "WiFi: Conectando...");
        sh1106_texto(2, 52, "Sincronizando hora...");
        sh1106_mostrar();
        return;
    }

    // ============================================================
    // 3. ZONA SUPERIOR: HORA GRANDE + INSIGNIA (Y = 2 a 16)
    // ============================================================
    char buffer_hora[16];
    snprintf(buffer_hora, sizeof(buffer_hora), "%02d:%02d:%02d", t.tm_hour, t.tm_min, t.tm_sec);
    sh1106_texto_grande(2, 2, buffer_hora);

    // Insignia de conectividad arriba a la derecha
    sh1106_texto(100, 6, hay_conexion() ? "WiFi" : "OFF");

    // Línea separadora superior
    sh1106_linea(0, 19, 127, 19);

    // ============================================================
    // 4. ZONA MEDIA: PRÓXIMO TIMBRE Y CUENTA REGRESIVA (Y = 23 a 44)
    // ============================================================
    if (t.tm_min != s_ultimo_minuto_prox || s_ultimo_minuto_prox == -1) {
        s_ultimo_minuto_prox = t.tm_min;
        s_hay_proximo_cache = horario_proximo(&t, &s_proximo_cache);
        s_especial_vigente_cache = horario_especial_vigente(&t);
        if (s_especial_vigente_cache) {
            horario_especial_nombre(s_especial_nombre_cache, sizeof(s_especial_nombre_cache));
        }
    }

    char linea[48];
    if (s_hay_proximo_cache) {
        snprintf(linea, sizeof(linea), "Prox: %s %s", s_proximo_cache.hora, s_proximo_cache.etiqueta);
        sh1106_texto(2, 23, linea);

        int hh = 0, mm = 0;
        sscanf(s_proximo_cache.hora, "%d:%d", &hh, &mm);
        int faltan = (hh * 3600 + mm * 60) - (t.tm_hour * 3600 + t.tm_min * 60 + t.tm_sec);
        if (faltan < 0) faltan = 0;
        snprintf(linea, sizeof(linea), "Faltan: %02d:%02d:%02d",
                 faltan / 3600, (faltan % 3600) / 60, faltan % 60);
        sh1106_texto(2, 35, linea);
    } else {
        sh1106_texto(2, 23, "Sin mas timbres hoy");
        sh1106_texto(2, 35, "Jornada finalizada");
    }

    // Línea separadora inferior
    sh1106_linea(0, 48, 127, 48);

    // ============================================================
    // 5. ZONA INFERIOR: BARRA DE ESTADO Y SENSORES (Y = 52)
    // ============================================================
    int estado_sismo = sismo_estado();

    if (estado_sismo >= 1) {
        // Alerta prioritaria si hay vibración sísmica detectada
        snprintf(linea, sizeof(linea), "! SISMO: %.2fg !", sismo_dynamic_magnitude());
    } else if (s_especial_vigente_cache) {
        snprintf(linea, sizeof(linea), "Esp: %s", s_especial_nombre_cache);
    } else if (!enlace_pareja_viva()) {
        snprintf(linea, sizeof(linea), "%s", ROL_ESCLAVO ? "M1: Sin enlace" : "M2: Sin enlace");
    } else {
        // En reposo normal: muestra temperatura RTC + MPU/UPS + Estado de red
        float temp = rtc_temperatura();
        char str_temp[10];
        if (temp > -50.0f) {
            snprintf(str_temp, sizeof(str_temp), "%.0fC", temp);
        } else {
            snprintf(str_temp, sizeof(str_temp), "RTC");
        }

        if (timbre_modo_ups()) {
            snprintf(linea, sizeof(linea), "%s UPS:ON NET:%s",
                     str_temp,
                     red_en_linea() ? "OK" : "OFF");
        } else {
            snprintf(linea, sizeof(linea), "%s MPU:%s NET:%s",
                     str_temp,
                     sismo_coprocesador_conectado() ? "OK" : "NO",
                     red_en_linea() ? "OK" : "OFF");
        }
    }
    sh1106_texto(2, 52, linea);

    sh1106_mostrar();
}
