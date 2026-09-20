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
#include "horario.h"
#include "pantalla.h"
#include "red.h"
#include "timbre.h"

static const char *TAG = "canal";

// Los mensajes del servidor son JSON compactos.
#define TAM_MENSAJE 256

typedef struct {
    char texto[TAM_MENSAJE];
} mensaje_ws_t;

static esp_websocket_client_handle_t s_cliente = NULL;
static QueueHandle_t s_cola = NULL;
static volatile bool s_conectado = false;
static volatile bool s_iniciado = false;

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
    case WEBSOCKET_EVENT_BEFORE_CONNECT:
        ESP_LOGI(TAG, "iniciando saludo WebSocket con el servidor...");
        break;

    case WEBSOCKET_EVENT_CONNECTED:
        s_conectado = true;
        ESP_LOGI(TAG, "conectado al servidor (WebSocket activo)");
        break;

    case WEBSOCKET_EVENT_DISCONNECTED:
        s_conectado = false;
        ESP_LOGW(TAG, "desconectado del servidor; reconectando...");
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
        ESP_LOGW(TAG, "error en el WebSocket (tipo=%d, status=%d)",
                 ev ? ev->error_handle.error_type : -1,
                 ev ? ev->error_handle.esp_ws_handshake_status_code : -1);
        s_conectado = false;
        break;

    default:
        break;
    }
}

// ============================================================
// 3. Arranque y Ciclo de Vida
// ============================================================

void canal_iniciar(void) {
    if (s_cola == NULL) {
        s_cola = xQueueCreate(4, sizeof(mensaje_ws_t));
        if (s_cola == NULL) {
            ESP_LOGE(TAG, "sin memoria para la cola del WebSocket");
        }
    }
}

void canal_conectar(void) {
    if (s_cliente != NULL) {
        if (!s_iniciado) {
            esp_err_t err = esp_websocket_client_start(s_cliente);
            if (err == ESP_OK) {
                s_iniciado = true;
            }
        }
        return;
    }

    canal_iniciar();

    char url[192];
    construir_url(url, sizeof(url));

    // La cabecera de autenticación, igual que en las peticiones HTTP de red.c.
    static char cabecera[128];
    snprintf(cabecera, sizeof(cabecera), "X-Device-Key: %s\r\n", DEVICE_API_KEY);

    esp_websocket_client_config_t cfg = {
        .uri = url,
        .headers = cabecera,
        .task_prio = 1,                 // Prioridad 1 (fondo, nunca bloquea el bucle de control a prioridad 3)
        .task_stack = 8192,             // 8 KB holgados para TLS y verificación de certificados
        .reconnect_timeout_ms = 10000,  // Reintento cada 10 s para no saturar CPU en caídas de red
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
    s_iniciado = true;

    ESP_LOGI(TAG, "canal WebSocket abierto hacia %s", url);
}

void canal_desconectar(void) {
    if (s_cliente != NULL && s_iniciado) {
        esp_websocket_client_stop(s_cliente);
        s_iniciado = false;
        s_conectado = false;
    }
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
        } else if (strcmp(tipo, "config") == 0) {
            const cJSON *ups = cJSON_GetObjectItemCaseSensitive(doc, "modoUps");
            const cJSON *dur = cJSON_GetObjectItemCaseSensitive(doc, "duracionManualSeg");
            const cJSON *umb = cJSON_GetObjectItemCaseSensitive(doc, "umbralSismicoG");
            const cJSON *smin = cJSON_GetObjectItemCaseSensitive(doc, "sismoDuracionMinMs");

            if (cJSON_IsBool(ups)) {
                bool modo = cJSON_IsTrue(ups);
                timbre_fijar_modo_ups(modo);
                pantalla_notificar_cambio("MODO UPS", modo ? "ACTIVADO" : "DESACTIVADO");
                ESP_LOGI(TAG, "modo UPS actualizado a: %s", modo ? "ON" : "OFF");
            }
            if (cJSON_IsNumber(dur)) {
                uint8_t d = (uint8_t)dur->valuedouble;
                timbre_fijar_duracion_manual(d);
                char det[32];
                snprintf(det, sizeof(det), "%d seg", d);
                pantalla_notificar_cambio("DURACION TIMBRE", det);
                ESP_LOGI(TAG, "duracion manual actualizada a: %d seg", d);
            }
            if (cJSON_IsNumber(umb) && cJSON_IsNumber(smin)) {
                horario_fijar_sismo((float)umb->valuedouble, (int)smin->valuedouble);
            }
        } else if (strcmp(tipo, "sincronizar") == 0) {
            const cJSON *motivo_json = cJSON_GetObjectItemCaseSensitive(doc, "motivo");
            const char *motivo = cJSON_GetStringValue(motivo_json);
            if (motivo != NULL && strcmp(motivo, "especial") == 0) {
                pantalla_notificar_cambio("HORARIO ESPECIAL", "ACTUALIZANDO...");
            } else {
                pantalla_notificar_cambio("HORARIOS", "ACTUALIZANDO...");
            }
            ESP_LOGI(TAG, "sincronización solicitada por el servidor (motivo: %s)", motivo ? motivo : "general");
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
void canal_conectar(void) { }
void canal_desconectar(void) { }
void canal_atender(void) { }
bool canal_conectado(void) { return false; }

#endif
