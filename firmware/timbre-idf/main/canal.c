//
//  canal.c
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//

#include "canal.h"

#include "config.h"

#if !ROL_ESCLAVO

#include <string.h>
#include <stdio.h>

#include "cJSON.h"
#include "comun.h"
#include "esp_crt_bundle.h"
#include "esp_log.h"
#include "esp_websocket_client.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "red.h"
#include "timbre.h"

static const char *TAG = "canal";

// Los mensajes del servidor son cortos: un JSON de menos de 128 bytes.
#define TAM_MENSAJE 128

typedef struct {
    char texto[TAM_MENSAJE];
} mensaje_ws_t;

static esp_websocket_client_handle_t s_cliente = NULL;
static QueueHandle_t s_cola = NULL;
static volatile bool s_conectado = false;

// ============================================================
// 1. Construir la URL del WebSocket
// ============================================================
//
// API_BASE es algo como "https://swiftyring.swiftydevs.dev/api" o
// "http://192.168.1.100:8080/api". El WebSocket va a la misma dirección
// pero con esquema ws:// o wss:// y ruta /api/dispositivo/canal.

static void construir_url(char *destino, size_t tam) {
    const char *base = API_BASE;
    const char *esquema_ws;
    const char *resto;  // lo que queda después de http:// o https://

    if (strncmp(base, "https://", 8) == 0) {
        esquema_ws = "wss://";
        resto = base + 8;
    } else if (strncmp(base, "http://", 7) == 0) {
        esquema_ws = "ws://";
        resto = base + 7;
    } else {
        esquema_ws = "ws://";
        resto = base;
    }

    // resto es "host:port/api" o "host/api". Se busca el primer "/" para
    // separar host de path, y se reemplaza "/api" por "/api/dispositivo/canal".
    const char *barra = strchr(resto, '/');
    if (barra != NULL) {
        // host = resto[0..barra), path = barra en adelante
        int largo_host = (int)(barra - resto);
        snprintf(destino, tam, "%s%.*s/api/dispositivo/canal", esquema_ws, largo_host, resto);
    } else {
        snprintf(destino, tam, "%s%s/api/dispositivo/canal", esquema_ws, resto);
    }
}

// ============================================================
// 2. Eventos del WebSocket
// ============================================================

static void manejar_evento(void *arg, esp_event_base_t base, int32_t id, void *datos) {
    esp_websocket_event_data_t *ev = (esp_websocket_event_data_t *)datos;

    switch (id) {
    case WEBSOCKET_EVENT_CONNECTED:
        s_conectado = true;
        ESP_LOGI(TAG, "conectado al servidor");
        break;

    case WEBSOCKET_EVENT_DISCONNECTED:
        s_conectado = false;
        ESP_LOGW(TAG, "desconectado; reconectando...");
        break;

    case WEBSOCKET_EVENT_DATA:
        // Solo interesan las tramas de texto (opcode 1). Las de ping/pong
        // las maneja el componente solo.
        if (ev->op_code != 0x01 || ev->data_len <= 0) break;

        mensaje_ws_t msg = {0};
        int copiar = ev->data_len < TAM_MENSAJE - 1 ? ev->data_len : TAM_MENSAJE - 1;
        memcpy(msg.texto, ev->data_ptr, copiar);
        msg.texto[copiar] = '\0';

        // A la cola sin esperar: si está llena se pierde el mensaje más
        // nuevo, pero no se bloquea la tarea del WebSocket.
        xQueueSend(s_cola, &msg, 0);
        break;

    case WEBSOCKET_EVENT_ERROR:
        ESP_LOGW(TAG, "error en el WebSocket");
        s_conectado = false;
        break;

    default:
        break;
    }
}

// ============================================================
// 3. Arranque
// ============================================================

void canal_iniciar(void) {
    s_cola = xQueueCreate(4, sizeof(mensaje_ws_t));
    if (s_cola == NULL) {
        ESP_LOGE(TAG, "sin memoria para la cola del WebSocket");
        return;
    }

    char url[192];
    construir_url(url, sizeof(url));

    // La cabecera de autenticación, igual que en las peticiones HTTP de red.c.
    static char cabecera[128];
    snprintf(cabecera, sizeof(cabecera), "X-Device-Key: %s\r\n", DEVICE_API_KEY);

    esp_websocket_client_config_t cfg = {
        .uri = url,
        .headers = cabecera,
        .reconnect_timeout_ms = 5000,
        .network_timeout_ms = 10000,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .pingpong_timeout_sec = 30,
        .ping_interval_sec = 25,
    };

    s_cliente = esp_websocket_client_init(&cfg);
    if (s_cliente == NULL) {
        ESP_LOGE(TAG, "no se pudo crear el cliente WebSocket");
        return;
    }

    esp_websocket_register_events(s_cliente, WEBSOCKET_EVENT_ANY, manejar_evento, NULL);
    esp_err_t err = esp_websocket_client_start(s_cliente);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "no se pudo abrir el WebSocket (%s)", esp_err_to_name(err));
        return;
    }

    ESP_LOGI(TAG, "canal WebSocket abierto hacia %s", url);
}

// ============================================================
// 4. Procesar mensajes (bucle de control)
// ============================================================

void canal_atender(void) {
    mensaje_ws_t msg;
    while (xQueueReceive(s_cola, &msg, 0) == pdTRUE) {
        cJSON *doc = cJSON_Parse(msg.texto);
        if (doc == NULL) {
            ESP_LOGW(TAG, "mensaje no es JSON válido");
            continue;
        }

        const cJSON *tipo_json = cJSON_GetObjectItemCaseSensitive(doc, "tipo");
        const char *tipo = cJSON_GetStringValue(tipo_json);

        if (tipo == NULL) {
            ESP_LOGW(TAG, "mensaje sin campo 'tipo'");
        } else if (strcmp(tipo, "timbrar") == 0) {
            const cJSON *dur = cJSON_GetObjectItemCaseSensitive(doc, "duracionSeg");
            int seg = cJSON_IsNumber(dur) ? (int)dur->valuedouble : 5;
            if (seg < 1) seg = 1;
            if (seg > 120) seg = 120;
            ESP_LOGI(TAG, "orden de timbrar recibida (%d s)", seg);
            timbre_pedir_desde_app((uint8_t)seg);
        } else if (strcmp(tipo, "sincronizar") == 0) {
            ESP_LOGI(TAG, "sincronización solicitada por el servidor");
            red_pedir_sincronizacion();
        } else {
            ESP_LOGD(TAG, "tipo desconocido: %s", tipo);
        }

        cJSON_Delete(doc);
    }
}

bool canal_conectado(void) {
    return s_conectado;
}

#else  // ROL_ESCLAVO

// El esclavo no habla con el servidor: todo le llega del maestro por ESP-NOW.
void canal_iniciar(void) { }
void canal_atender(void) { }
bool canal_conectado(void) { return false; }

#endif
