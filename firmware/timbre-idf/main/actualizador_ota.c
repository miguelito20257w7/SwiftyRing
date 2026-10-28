//
//  actualizador_ota.c
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//

#include "actualizador_ota.h"
#include <string.h>
#include "esp_log.h"
#include "esp_https_ota.h"
#include "esp_ota_ops.h"
#include "esp_crt_bundle.h"
#include "esp_system.h"
#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "pantalla.h"
#include "config.h"

static const char *TAG = "ota_https";
static bool s_en_curso = false;
static char s_url_ota[256] = "";

bool actualizador_ota_en_curso(void) {
    return s_en_curso;
}

void actualizador_ota_confirmar_arranque(void) {
    esp_ota_img_states_t ota_state;
    const esp_partition_t *running = esp_ota_get_running_partition();

    if (esp_ota_get_state_partition(running, &ota_state) == ESP_OK) {
        if (ota_state == ESP_OTA_IMG_PENDING_VERIFY) {
            ESP_LOGW(TAG, "Firmware nuevo arrancó correctamente: confirmando partición y cancelando rollback");
            esp_ota_mark_app_valid_cancel_rollback();
        }
    }
}

static void tarea_ota(void *pvParameter) {
    ESP_LOGI(TAG, "Iniciando proceso OTA desde: %s", s_url_ota);

    // Seguridad: Apagar el relé del timbre (lógica activa en BAJO -> 1 = apagado)
    gpio_set_level(PIN_RELE, 1);
#ifdef PIN_RELE_UPS
    gpio_set_level(PIN_RELE_UPS, 1);
#endif

    pantalla_mensaje("ACTUALIZANDO", "DESCARGANDO...");

    esp_http_client_config_t http_config = {
        .url = s_url_ota,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = 30000,
        .keep_alive_enable = true,
    };

    esp_https_ota_config_t ota_config = {
        .http_config = &http_config,
    };

    esp_err_t ret = esp_https_ota(&ota_config);
    if (ret == ESP_OK) {
        ESP_LOGI(TAG, "Actualización OTA completada con éxito. Reiniciando...");
        pantalla_mensaje("ACTUALIZADO", "REINICIANDO...");
        vTaskDelay(pdMS_TO_TICKS(1500));
        esp_restart();
    } else {
        ESP_LOGE(TAG, "Fallo durante la actualización OTA: %s", esp_err_to_name(ret));
        pantalla_notificar_cambio("ERROR OTA", "FALLO DESCARGA");
        s_en_curso = false;
        vTaskDelete(NULL);
    }
}

esp_err_t actualizador_ota_iniciar(const char *url_binario) {
    if (!url_binario || strlen(url_binario) == 0) return ESP_ERR_INVALID_ARG;
    if (s_en_curso) {
        ESP_LOGW(TAG, "Ya hay una actualización OTA en curso");
        return ESP_ERR_INVALID_STATE;
    }

    strlcpy(s_url_ota, url_binario, sizeof(s_url_ota));
    s_en_curso = true;

    BaseType_t res = xTaskCreate(tarea_ota, "tarea_ota_https", 8192, NULL, 5, NULL);
    return (res == pdPASS) ? ESP_OK : ESP_FAIL;
}
