//
//  led_rgb.c
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  Control del LED RGB direccionable (WS2812) en la placa ESP32-S3.
//

#include "led_rgb.h"

#include "comun.h"
#include "config.h"
#include "esp_log.h"

#if defined(CONFIG_IDF_TARGET_ESP32S3) && defined(PIN_RGB_LED)
#include "led_strip.h"

static const char *TAG = "led_rgb";
static led_strip_handle_t s_led_strip = NULL;
static bool s_estaba_activo = false;
static uint32_t s_ultimo_cambio = 0;
static uint8_t s_fase = 0;

void led_rgb_iniciar(void) {
    ESP_LOGI(TAG, "Inicializando LED RGB en GPIO %d", PIN_RGB_LED);
    led_strip_config_t strip_config = {
        .strip_gpio_num = PIN_RGB_LED,
        .max_leds = 1,
        .led_model = LED_MODEL_WS2812,
        .color_component_format = LED_STRIP_COLOR_COMPONENT_FMT_GRB,
        .flags.invert_out = false,
    };
    led_strip_rmt_config_t rmt_config = {
        .clk_src = RMT_CLK_SRC_DEFAULT,
        .resolution_hz = 10 * 1000 * 1000,  // 10 MHz
        .flags.with_dma = false,
    };

    esp_err_t err = led_strip_new_rmt_device(&strip_config, &rmt_config, &s_led_strip);
    if (err == ESP_OK && s_led_strip != NULL) {
        led_strip_clear(s_led_strip);
        ESP_LOGI(TAG, "LED RGB iniciado correctamente");
    } else {
        ESP_LOGE(TAG, "Error al inicializar LED RGB (%s)", esp_err_to_name(err));
        s_led_strip = NULL;
    }
}

void led_rgb_atender(bool timbre_activo) {
    if (s_led_strip == NULL) return;

    uint32_t ahora = millis();

    if (timbre_activo) {
        s_estaba_activo = true;
        // Titileo estroboscópico de alto impacto visual (cambio cada 75 ms)
        if (ahora - s_ultimo_cambio >= 75) {
            s_ultimo_cambio = ahora;
            s_fase = (s_fase + 1) % 4;

            switch (s_fase) {
                case 0:
                    // Rojo Intenso
                    led_strip_set_pixel(s_led_strip, 0, 255, 0, 0);
                    break;
                case 1:
                    // Blanco Brillante (Destello)
                    led_strip_set_pixel(s_led_strip, 0, 255, 255, 255);
                    break;
                case 2:
                    // Rojo Intenso
                    led_strip_set_pixel(s_led_strip, 0, 255, 0, 0);
                    break;
                case 3:
                    // Amarillo Vivo
                    led_strip_set_pixel(s_led_strip, 0, 255, 200, 0);
                    break;
            }
            led_strip_refresh(s_led_strip);
        }
    } else if (s_estaba_activo) {
        // Al terminar el timbre, apagar el LED por completo
        s_estaba_activo = false;
        s_fase = 0;
        led_strip_clear(s_led_strip);
    }
}

#else

// No-op para placas sin LED RGB o ESP32 WROOM
void led_rgb_iniciar(void) {}
void led_rgb_atender(bool timbre_activo) { (void)timbre_activo; }

#endif
