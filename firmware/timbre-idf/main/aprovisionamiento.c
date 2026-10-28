//
//  aprovisionamiento.c
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//

#include "aprovisionamiento.h"
#include <string.h>
#include "esp_log.h"
#include "esp_wifi.h"
#include "esp_netif.h"
#include "esp_mac.h"
#include "esp_http_server.h"
#include "cJSON.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "almacen_config.h"
#include "pantalla.h"

static const char *TAG = "ap_setup";

static bool s_activo = false;
static char s_ssid_ap[32] = "SwiftyRing-Setup";
static httpd_handle_t s_servidor = NULL;
static esp_netif_t *s_netif_ap = NULL;

void aprovisionamiento_obtener_ssid_ap(char *buf, size_t max_len) {
    if (buf && max_len > 0) {
        strlcpy(buf, s_ssid_ap, max_len);
    }
}

bool aprovisionamiento_activo(void) {
    return s_activo;
}

static void tarea_reinicio_diferido(void *arg) {
    vTaskDelay(pdMS_TO_TICKS(1500));
    esp_restart();
}

// GET /api/info
static esp_err_t manejador_info(httpd_req_t *req) {
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");

    cJSON *raiz = cJSON_CreateObject();
    cJSON_AddStringToObject(raiz, "dispositivo", "SwiftyRing ESP32-C3");
    cJSON_AddStringToObject(raiz, "ssid_ap", s_ssid_ap);
    cJSON_AddStringToObject(raiz, "version", "1.3.0");

    char *json_str = cJSON_PrintUnformatted(raiz);
    httpd_resp_sendstr(req, json_str);
    free(json_str);
    cJSON_Delete(raiz);
    return ESP_OK;
}

// GET /api/scan - Escaneo de redes WiFi disponibles
static esp_err_t manejador_scan(httpd_req_t *req) {
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");

    wifi_scan_config_t scan_config = {
        .ssid = NULL,
        .bssid = NULL,
        .channel = 0,
        .show_hidden = false,
        .scan_type = WIFI_SCAN_TYPE_ACTIVE
    };

    esp_wifi_scan_start(&scan_config, true);

    uint16_t num_redes = 0;
    esp_wifi_scan_get_ap_num(&num_redes);
    if (num_redes > 20) num_redes = 20;

    wifi_ap_record_t *ap_records = malloc(sizeof(wifi_ap_record_t) * num_redes);
    cJSON *raiz = cJSON_CreateArray();

    if (ap_records && esp_wifi_scan_get_ap_records(&num_redes, ap_records) == ESP_OK) {
        for (int i = 0; i < num_redes; i++) {
            if (strlen((char *)ap_records[i].ssid) == 0) continue;
            cJSON *item = cJSON_CreateObject();
            cJSON_AddStringToObject(item, "ssid", (char *)ap_records[i].ssid);
            cJSON_AddNumberToObject(item, "rssi", ap_records[i].rssi);
            cJSON_AddNumberToObject(item, "auth", ap_records[i].authmode);
            cJSON_AddItemToArray(raiz, item);
        }
    }
    if (ap_records) free(ap_records);

    char *json_str = cJSON_PrintUnformatted(raiz);
    httpd_resp_sendstr(req, json_str);
    free(json_str);
    cJSON_Delete(raiz);
    return ESP_OK;
}

// POST /api/setup - Recibe JSON con credenciales
static esp_err_t manejador_setup(httpd_req_t *req) {
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");

    char buffer[512];
    int recibido = httpd_req_recv(req, buffer, sizeof(buffer) - 1);
    if (recibido <= 0) {
        httpd_resp_send_500(req);
        return ESP_FAIL;
    }
    buffer[recibido] = '\0';

    cJSON *raiz = cJSON_Parse(buffer);
    if (!raiz) {
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "JSON no válido");
        return ESP_FAIL;
    }

    cJSON *j_ssid = cJSON_GetObjectItem(raiz, "ssid");
    cJSON *j_pass = cJSON_GetObjectItem(raiz, "password");
    cJSON *j_api = cJSON_GetObjectItem(raiz, "api_base");
    cJSON *j_key = cJSON_GetObjectItem(raiz, "device_api_key");

    if (!cJSON_IsString(j_ssid) || strlen(j_ssid->valuestring) == 0) {
        cJSON_Delete(raiz);
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "SSID obligatorio");
        return ESP_FAIL;
    }

    const char *ssid = j_ssid->valuestring;
    const char *pass = (cJSON_IsString(j_pass)) ? j_pass->valuestring : "";
    const char *api = (cJSON_IsString(j_api) && strlen(j_api->valuestring) > 0) ? j_api->valuestring : "https://swiftyring.swiftydevs.dev/api";
    const char *key = (cJSON_IsString(j_key)) ? j_key->valuestring : "dev-esp32-timbre-2026";

    ESP_LOGI(TAG, "Guardando configuración: SSID='%s', API='%s'", ssid, api);
    esp_err_t err = almacen_config_guardar(ssid, pass, api, key);
    cJSON_Delete(raiz);

    if (err != ESP_OK) {
        httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "Error al guardar en NVS");
        return ESP_FAIL;
    }

    pantalla_mensaje("GUARDADO", "REINICIANDO...");

    httpd_resp_sendstr(req, "{\"status\":\"ok\",\"mensaje\":\"Configuracion guardada. Reiniciando modulo...\"}");

    // Reiniciar tras contestar la petición HTTP
    xTaskCreate(tarea_reinicio_diferido, "reinicio_post_setup", 2048, NULL, 5, NULL);
    return ESP_OK;
}

// POST /api/reset - Restablecimiento de fábrica remoto
static esp_err_t manejador_reset(httpd_req_t *req) {
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");

    almacen_config_restablecer_fabrica();
    pantalla_mensaje("RESTABLECIENDO", "DE FABRICA...");

    httpd_resp_sendstr(req, "{\"status\":\"ok\",\"mensaje\":\"Restablecimiento iniciado\"}");
    xTaskCreate(tarea_reinicio_diferido, "reinicio_reset", 2048, NULL, 5, NULL);
    return ESP_OK;
}

// OPTIONS para CORS preflight
static esp_err_t manejador_options(httpd_req_t *req) {
    httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
    httpd_resp_set_hdr(req, "Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    httpd_resp_set_hdr(req, "Access-Control-Allow-Headers", "Content-Type");
    httpd_resp_send(req, NULL, 0);
    return ESP_OK;
}

static void iniciar_servidor_web(void) {
    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.server_port = 80;
    config.ctrl_port = 32768;
    config.max_uri_handlers = 8;

    if (httpd_start(&s_servidor, &config) == ESP_OK) {
        httpd_uri_t uri_info = { .uri = "/api/info", .method = HTTP_GET, .handler = manejador_info };
        httpd_register_uri_handler(s_servidor, &uri_info);

        httpd_uri_t uri_scan = { .uri = "/api/scan", .method = HTTP_GET, .handler = manejador_scan };
        httpd_register_uri_handler(s_servidor, &uri_scan);

        httpd_uri_t uri_setup = { .uri = "/api/setup", .method = HTTP_POST, .handler = manejador_setup };
        httpd_register_uri_handler(s_servidor, &uri_setup);

        httpd_uri_t uri_reset = { .uri = "/api/reset", .method = HTTP_POST, .handler = manejador_reset };
        httpd_register_uri_handler(s_servidor, &uri_reset);

        httpd_uri_t uri_options = { .uri = "/api/*", .method = HTTP_OPTIONS, .handler = manejador_options };
        httpd_register_uri_handler(s_servidor, &uri_options);

        ESP_LOGI(TAG, "Servidor HTTP de aprovisionamiento iniciado en puerto 80");
    }
}

esp_err_t aprovisionamiento_iniciar(void) {
    if (s_activo) return ESP_OK;

    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP);
    snprintf(s_ssid_ap, sizeof(s_ssid_ap), "SwiftyRing-%02X%02X", mac[4], mac[5]);

    ESP_LOGW(TAG, "Iniciando Modo Aprovisionamiento. SoftAP: %s (IP 192.168.4.1)", s_ssid_ap);

    if (!s_netif_ap) {
        s_netif_ap = esp_netif_create_default_wifi_ap();
    }

    wifi_config_t wifi_config = {
        .ap = {
            .channel = 1,
            .max_connection = 4,
            .authmode = WIFI_AUTH_OPEN,
            .beacon_interval = 100
        },
    };
    strlcpy((char *)wifi_config.ap.ssid, s_ssid_ap, sizeof(wifi_config.ap.ssid));
    wifi_config.ap.ssid_len = strlen(s_ssid_ap);

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_APSTA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &wifi_config));
    ESP_ERROR_CHECK(esp_wifi_start());

    iniciar_servidor_web();
    s_activo = true;

    return ESP_OK;
}

void aprovisionamiento_detener(void) {
    if (!s_activo) return;
    if (s_servidor) {
        httpd_stop(s_servidor);
        s_servidor = NULL;
    }
    s_activo = false;
    ESP_LOGI(TAG, "Modo aprovisionamiento detenido");
}
