//
//  timbre.c
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//

#include "timbre.h"

#include <string.h>

#include "comun.h"
#include "config.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "red.h"

static const char *TAG = "timbre";

static bool s_activo = false;
static uint32_t s_hasta = 0;  // millis() en que se apaga el relé
static char s_motivo[33] = "";

// Orden dejada por la tarea de red. `volatile` porque la escribe una tarea y
// la lee otra.
static volatile uint8_t s_orden_app_seg = 0;

void timbre_iniciar(void) {
    gpio_config_t rele = {
        .pin_bit_mask = 1ULL << PIN_RELE,
        .mode = GPIO_MODE_OUTPUT,
    };
    gpio_config(&rele);
    gpio_set_level(PIN_RELE, 0);

    gpio_config_t boton = {
        .pin_bit_mask = 1ULL << PIN_BOTON,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    gpio_config(&boton);
}

void timbre_activar(uint8_t duracion_seg, const char *motivo) {
    gpio_set_level(PIN_RELE, 1);
    s_activo = true;
    s_hasta = millis() + (uint32_t)duracion_seg * 1000;
    strlcpy(s_motivo, motivo, sizeof(s_motivo));
}

void timbre_pedir_desde_app(uint8_t duracion_seg) { s_orden_app_seg = duracion_seg; }

bool timbre_activo(void) { return s_activo; }

const char *timbre_motivo(void) { return s_motivo; }

// El botón físico (RF-15): flanco de bajada más 400 ms de guarda contra
// rebotes del contacto y contra dedos ansiosos.
static void atender_boton(void) {
    static uint32_t ultima_pulsacion = 0;
    static int estado_anterior = 1;

    int estado = gpio_get_level(PIN_BOTON);
    if (estado_anterior == 1 && estado == 0 && millis() - ultima_pulsacion > 400) {
        ultima_pulsacion = millis();
        ESP_LOGI(TAG, "botón físico");
        timbre_activar(5, "Manual");
        red_encolar_activacion("manual_fisico", NULL, 5);  // RF-17
    }
    estado_anterior = estado;
}

void timbre_atender(void) {
    if (s_activo && millis() >= s_hasta) {
        gpio_set_level(PIN_RELE, 0);
        s_activo = false;
    }

    uint8_t orden = s_orden_app_seg;
    if (orden > 0) {
        s_orden_app_seg = 0;
        ESP_LOGI(TAG, "orden desde la app");
        // No se reporta: el backend ya registró la activación manual_app al
        // emitir la orden. Reportarla aquí la duplicaría.
        timbre_activar(orden, "Desde la app");
    }

    atender_boton();
}
