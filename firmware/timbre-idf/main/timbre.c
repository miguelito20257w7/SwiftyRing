//
//  timbre.c
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//

#include "timbre.h"

#include <string.h>

#include "comun.h"
#include "config.h"
#include "driver/gpio.h"
#include "enlace.h"
#include "esp_log.h"
#include "pantalla.h"
#include "red.h"

static const char *TAG = "timbre";

static bool s_activo = false;
static uint32_t s_hasta = 0;  // millis() en que se apaga el relé
static char s_motivo[33] = "";
static bool s_modo_ups = false;
static uint8_t s_duracion_manual_seg = 5;

// Orden dejada por la tarea de red. `volatile` porque la escribe una tarea y
// la lee otra.
static volatile uint8_t s_orden_app_seg = 0;

void timbre_iniciar(void) {
    gpio_config_t rele = {
        .pin_bit_mask = 1ULL << PIN_RELE,
        .mode = GPIO_MODE_OUTPUT,
    };
    gpio_config(&rele);
    gpio_set_level(PIN_RELE, 1);

#ifdef PIN_RELE_UPS
    gpio_config_t rele_ups = {
        .pin_bit_mask = 1ULL << PIN_RELE_UPS,
        .mode = GPIO_MODE_OUTPUT,
    };
    gpio_config(&rele_ups);
    // El módulo de relé tiene lógica inversa: 1 = apagado, 0 = encendido
    gpio_set_level(PIN_RELE_UPS, 1);
#endif

#if !ROL_ESCLAVO
    // El esclavo no lleva botón: su placa no tiene nada cableado a ese pin y
    // configurarlo con pull-up solo serviría para leer ruido.
    gpio_config_t boton = {
        .pin_bit_mask = 1ULL << PIN_BOTON,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    gpio_config(&boton);
#endif
}

void timbre_activar(uint8_t duracion_seg, const char *motivo) {
    gpio_set_level(PIN_RELE, 0);
    s_activo = true;
    s_hasta = millis() + (uint32_t)duracion_seg * 1000;
    strlcpy(s_motivo, motivo, sizeof(s_motivo));
}

void timbre_pedir_desde_app(uint8_t duracion_seg) { s_orden_app_seg = duracion_seg; }

bool timbre_activo(void) { return s_activo; }

const char *timbre_motivo(void) { return s_motivo; }

void timbre_fijar_modo_ups(bool activo) {
    s_modo_ups = activo;
#ifdef PIN_RELE_UPS
    // Lógica inversa: 0 = encendido/activado, 1 = apagado/desactivado
    gpio_set_level(PIN_RELE_UPS, activo ? 0 : 1);
    ESP_LOGI(TAG, "modo UPS: %s (GPIO %d = %d)", activo ? "ACTIVADO" : "DESACTIVADO", PIN_RELE_UPS, activo ? 0 : 1);
#endif
}

bool timbre_modo_ups(void) { return s_modo_ups; }

void timbre_fijar_duracion_manual(uint8_t duracion_seg) {
    if (duracion_seg >= 1 && duracion_seg <= 60) {
        s_duracion_manual_seg = duracion_seg;
        ESP_LOGI(TAG, "duración timbre manual: %u s", duracion_seg);
    }
}

uint8_t timbre_duracion_manual(void) { return s_duracion_manual_seg; }

// El botón físico (RF-15): flanco de bajada más 150 ms de guarda contra
// rebotes del contacto (respuesta instantánea al presionar). Solo lo tiene el
// maestro; el esclavo timbra por horario, por sismo o cuando el maestro se lo
// ordena.
#if !ROL_ESCLAVO
static void atender_boton(void) {
    static int estado_anterior = 1;
    static uint32_t t_presionado = 0;
    static bool accion_larga_disparada = false;

    int estado = gpio_get_level(PIN_BOTON);

    // Flanco de bajada: se comenzó a presionar el botón físico
    if (estado_anterior == 1 && estado == 0) {
        t_presionado = millis();
        accion_larga_disparada = false;
    }
    // Mientras permanece presionado:
    else if (estado == 0) {
        uint32_t tiempo_mantenido = millis() - t_presionado;
        // Si se mantiene presionado por 5 segundos (5000 ms), conmuta Modo UPS
        if (!accion_larga_disparada && tiempo_mantenido >= 5000) {
            accion_larga_disparada = true;
            bool nuevo_ups = !timbre_modo_ups();
            timbre_fijar_modo_ups(nuevo_ups);
            ESP_LOGW(TAG, "¡Botón presionado por 5 s! Modo UPS: %s", nuevo_ups ? "ACTIVADO" : "DESACTIVADO");
            pantalla_notificar_cambio("MODO UPS", nuevo_ups ? "ACTIVADO" : "DESACTIVADO");
        }
    }
    // Flanco de subida: se soltó el botón
    else if (estado_anterior == 0 && estado == 1) {
        uint32_t tiempo_mantenido = millis() - t_presionado;
        // Si no fue pulsación larga de 5 s y superó el antirrebote (mínimo 50 ms):
        if (!accion_larga_disparada && tiempo_mantenido >= 50) {
            uint8_t dur = s_duracion_manual_seg;
            ESP_LOGI(TAG, "Botón físico liberado tras %lu ms -> activando timbre (%u s)",
                     (unsigned long)tiempo_mantenido, dur);
            timbre_activar(dur, "Manual");
            red_encolar_activacion("manual_fisico", NULL, dur);  // RF-17
            // Que suene también en el otro edificio vía ESP-NOW
            enlace_ordenar_alarma(dur, "Manual");
        }
    }

    estado_anterior = estado;
}
#endif

void timbre_atender(void) {
    if (s_activo && millis() >= s_hasta) {
        gpio_set_level(PIN_RELE, 1);
        s_activo = false;
    }

    uint8_t orden = s_orden_app_seg;
    if (orden > 0) {
        s_orden_app_seg = 0;
        ESP_LOGI(TAG, "orden desde la app");
        // No se reporta: el backend ya registró la activación manual_app al
        // emitir la orden. Reportarla aquí la duplicaría.
        timbre_activar(orden, "Desde la app");
        enlace_ordenar_alarma(orden, "Desde la app");
    }

#if !ROL_ESCLAVO
    atender_boton();
#endif
}
