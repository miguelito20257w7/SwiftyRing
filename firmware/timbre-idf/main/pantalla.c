//
//  pantalla.c
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//

#include "pantalla.h"

#include <stdio.h>
#include <string.h>

#include "horario.h"
#include "red.h"
#include "reloj.h"
#include "sh1106.h"
#include "timbre.h"

void pantalla_iniciar(i2c_master_bus_handle_t bus) { sh1106_iniciar(bus); }

void pantalla_mensaje(const char *linea1, const char *linea2) {
    sh1106_limpiar();
    sh1106_texto_grande(2, 12, linea1);
    sh1106_texto(2, 40, linea2);
    sh1106_mostrar();
}

// Icono de "sin conexión" (RF-27), arriba a la derecha: las tres barritas de
// señal con un tajo diagonal. El tajo se dibuja APAGANDO píxeles, que es como
// se marca algo tachado en una pantalla de un solo color.
static void dibujar_icono_sin_red(void) {
    const int x = 106;

    sh1106_rect(x, 8, 3, 5);        // barra corta
    sh1106_rect(x + 5, 5, 3, 8);    // barra media
    sh1106_rect(x + 10, 2, 3, 11);  // barra alta

    // El tajo baja 8 píxeles a lo largo de 15, para cruzar las tres barras por
    // el medio y no por la punta. De ahí el (i * 8) / 15.
    for (int i = 0; i <= 15; i++) {
        int y = 12 - (i * 8) / 15;
        sh1106_pixel(x - 1 + i, y, false);
        sh1106_pixel(x - 1 + i, y - 1, false);
    }
}

void pantalla_dibujar(void) {
    if (!sh1106_presente()) return;

    // RF-26: mientras suena, la pantalla entera es el indicador.
    if (timbre_activo()) {
        sh1106_limpiar();
        sh1106_texto_grande(16, 16, "¡TIMBRE!");
        sh1106_texto(16, 44, timbre_motivo());
        sh1106_mostrar();
        return;
    }

    sh1106_limpiar();

    struct tm t;
    if (!reloj_hora_local(&t)) {
        sh1106_texto_grande(2, 12, "Sin hora");
        sh1106_texto(2, 40, "Esperando red...");
        if (!red_en_linea()) dibujar_icono_sin_red();
        sh1106_mostrar();
        return;
    }

    // Hora actual, grande (RF-25). El buffer da de sobra para la línea más
    // larga ("Prox: " + hora + una etiqueta de 32 letras): en la pantalla solo
    // caben 21 caracteres, pero se arma el texto entero y lo recorta el
    // dibujado, no el snprintf.
    char linea[64];
    snprintf(linea, sizeof(linea), "%02d:%02d:%02d", t.tm_hour, t.tm_min, t.tm_sec);
    sh1106_texto_grande(2, 1, linea);

    if (!red_en_linea()) dibujar_icono_sin_red();  // RF-27

    // Próximo timbre y cuenta atrás (RF-25).
    timbre_programado_t proximo;
    if (horario_proximo(&t, &proximo)) {
        snprintf(linea, sizeof(linea), "Prox: %s %s", proximo.hora, proximo.etiqueta);
        sh1106_texto(0, 26, linea);

        int hh = 0, mm = 0;
        sscanf(proximo.hora, "%d:%d", &hh, &mm);
        int faltan = (hh * 3600 + mm * 60) - (t.tm_hour * 3600 + t.tm_min * 60 + t.tm_sec);
        if (faltan < 0) faltan = 0;
        snprintf(linea, sizeof(linea), "Faltan %02d:%02d:%02d", faltan / 3600,
                 (faltan % 3600) / 60, faltan % 60);
        sh1106_texto(0, 38, linea);
    } else {
        sh1106_texto(0, 26, "Sin mas timbres hoy");
    }

    // Si rige un horario especial, se dice abajo (RF-10).
    if (horario_especial_vigente(&t)) {
        char nombre[33];
        horario_especial_nombre(nombre, sizeof(nombre));
        snprintf(linea, sizeof(linea), "Especial: %s", nombre);
        sh1106_texto(0, 52, linea);
    }

    sh1106_mostrar();
}
