//
//  almacen_config.c
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//

#include "almacen_config.h"
#include <string.h>
#include "esp_log.h"
#include "nvs_flash.h"
#include "nvs.h"
#include "esp_system.h"
#include "config.h"

static const char *TAG = "config_nvs";
static const char *NVS_NAMESPACE = "swifty_cfg";
static modulo_config_t s_cached_cfg;
static bool s_cached_cargada = false;

static void asegurar_cache(void) {
    if (!s_cached_cargada) {
        almacen_config_leer(&s_cached_cfg);
        s_cached_cargada = true;
    }
}

const char *almacen_config_api_base(void) {
    asegurar_cache();
    if (strlen(s_cached_cfg.api_base) > 0) return s_cached_cfg.api_base;
    return API_BASE;
}

const char *almacen_config_device_key(void) {
    asegurar_cache();
    if (strlen(s_cached_cfg.device_api_key) > 0) return s_cached_cfg.device_api_key;
    return DEVICE_API_KEY;
}

const char *almacen_config_wifi_ssid(void) {
    asegurar_cache();
    return s_cached_cfg.wifi_ssid;
}

const char *almacen_config_wifi_pass(void) {
    asegurar_cache();
    return s_cached_cfg.wifi_password;
}

esp_err_t almacen_config_iniciar(void) {
    // nvs_flash_init() ya se invoca en main.c, pero verificamos que el namespace abra bien
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE, NVS_READONLY, &handle);
    if (err == ESP_OK) {
        nvs_close(handle);
    }
    return ESP_OK;
}

bool almacen_config_esta_configurado(void) {
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE, NVS_READONLY, &handle);
    if (err != ESP_OK) {
        return false;
    }

    size_t required_size = 0;
    err = nvs_get_str(handle, "ssid", NULL, &required_size);
    nvs_close(handle);

    return (err == ESP_OK && required_size > 1);
}

esp_err_t almacen_config_leer(modulo_config_t *cfg) {
    if (!cfg) return ESP_ERR_INVALID_ARG;
    memset(cfg, 0, sizeof(modulo_config_t));

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE, NVS_READONLY, &handle);
    if (err != ESP_OK) {
        // Fallback a los valores de desarrollo definidos en config.h si existen
#ifdef WIFI_SSID
        if (strcmp(WIFI_SSID, "NOMBRE_DE_LA_RED") != 0) {
            strlcpy(cfg->wifi_ssid, WIFI_SSID, sizeof(cfg->wifi_ssid));
            strlcpy(cfg->wifi_password, WIFI_PASSWORD, sizeof(cfg->wifi_password));
            strlcpy(cfg->api_base, API_BASE, sizeof(cfg->api_base));
            strlcpy(cfg->device_api_key, DEVICE_API_KEY, sizeof(cfg->device_api_key));
            return ESP_OK;
        }
#endif
        return err;
    }

    size_t size = sizeof(cfg->wifi_ssid);
    nvs_get_str(handle, "ssid", cfg->wifi_ssid, &size);

    size = sizeof(cfg->wifi_password);
    nvs_get_str(handle, "pass", cfg->wifi_password, &size);

    size = sizeof(cfg->api_base);
    nvs_get_str(handle, "api_base", cfg->api_base, &size);

    size = sizeof(cfg->device_api_key);
    nvs_get_str(handle, "api_key", cfg->device_api_key, &size);

    nvs_close(handle);

    // Si api_base quedó vacío, asignar default institucional
    if (strlen(cfg->api_base) == 0) {
        strlcpy(cfg->api_base, "https://swiftyring.swiftydevs.dev/api", sizeof(cfg->api_base));
    }

    return (strlen(cfg->wifi_ssid) > 0) ? ESP_OK : ESP_ERR_NOT_FOUND;
}

esp_err_t almacen_config_guardar(const char *ssid, const char *pass, const char *api_base, const char *api_key) {
    if (!ssid || strlen(ssid) == 0) return ESP_ERR_INVALID_ARG;

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE, NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "error al abrir NVS para guardar: %s", esp_err_to_name(err));
        return err;
    }

    err = nvs_set_str(handle, "ssid", ssid);
    if (err == ESP_OK && pass) {
        err = nvs_set_str(handle, "pass", pass);
    }
    if (err == ESP_OK && api_base) {
        err = nvs_set_str(handle, "api_base", api_base);
    }
    if (err == ESP_OK && api_key) {
        err = nvs_set_str(handle, "api_key", api_key);
    }

    if (err == ESP_OK) {
        err = nvs_commit(handle);
        ESP_LOGI(TAG, "configuración guardada exitosamente en NVS");
    }

    nvs_close(handle);
    return err;
}

esp_err_t almacen_config_restablecer_fabrica(void) {
    ESP_LOGW(TAG, "Restableciendo configuración de fábrica (borrando NVS)...");
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE, NVS_READWRITE, &handle);
    if (err == ESP_OK) {
        nvs_erase_all(handle);
        nvs_commit(handle);
        nvs_close(handle);
    }
    return ESP_OK;
}
