//
//  red.c
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//

#include "red.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "cJSON.h"
#include "comun.h"
#include "config.h"
#include "esp_crt_bundle.h"
#include "esp_event.h"
#include "esp_http_client.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "horario.h"
#include "timbre.h"
#include "canal.h"

static const char *TAG = "red";

// La cola de reportes vive en la flash. Mientras se envía, el archivo se
// aparta con otro nombre para no bloquear al resto del firmware.
#define RUTA_COLA RUTA_ALMACEN "/reportes.jsonl"
#define RUTA_ENVIANDO RUTA_ALMACEN "/enviando.jsonl"

#define INTERVALO_COMANDOS_MS 10000             // Respaldo de WS: consulta de comandos (10 s)
#define INTERVALO_SYNC_MS (30 * 60 * 1000)
#define INTERVALO_FLUSH_MS 15000
#define INTERVALO_WIFI_MS 10000

// Por HTTPS cada petición empieza por un saludo TLS, que tarda bastante más
// que una conexión pelada. Cuatro segundos se quedaban cortos.
#define TIEMPO_MAXIMO_MS 10000

// El JSON del horario completo: 32 timbres habituales + los del especial.
#define TAM_RESPUESTA_HORARIO 12288

static volatile bool s_en_linea = false;
static volatile bool s_conectando = false;
static volatile bool s_flush_pedido = false;
static volatile bool s_sync_pedido = false;
static SemaphoreHandle_t s_candado_cola;

// ============================================================
// 1. WiFi
// ============================================================

static void manejar_evento(void *arg, esp_event_base_t base, int32_t id, void *datos) {
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        s_conectando = true;
        esp_wifi_connect();
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        wifi_event_sta_disconnected_t *ev = (wifi_event_sta_disconnected_t *)datos;
        s_en_linea = false;
        s_conectando = false;
        ESP_LOGW(TAG, "sin conexión (motivo: %d)", ev ? ev->reason : -1);
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *evento = (ip_event_got_ip_t *)datos;
        ESP_LOGI(TAG, "conectado, IP " IPSTR, IP2STR(&evento->ip_info.ip));
        s_en_linea = true;
        s_conectando = false;
    }
}

void red_iniciar(void) {
    s_candado_cola = xSemaphoreCreateMutex();

    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&init));

    ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID,
                                                        manejar_evento, NULL, NULL));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_GOT_IP,
                                                        manejar_evento, NULL, NULL));

    wifi_config_t cfg = {
        .sta = {
            .ssid = WIFI_SSID,
            .password = WIFI_PASSWORD,
            .scan_method = WIFI_ALL_CHANNEL_SCAN,
            .sort_method = WIFI_CONNECT_AP_BY_SIGNAL,
            .ft_enabled = 1,
            .btm_enabled = 1,
            .rm_enabled = 1,
        },
    };
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &cfg));
    ESP_ERROR_CHECK(esp_wifi_start());

    // Sin ahorro de energía: por defecto la radio se duerme a ratos entre
    // balizas del router, y dormida no oye las tramas de ESP-NOW que le manda
    // el esclavo (enlace.c). Gasta un poco más, pero el módulo está enchufado.
    ESP_ERROR_CHECK(esp_wifi_set_ps(WIFI_PS_NONE));

    ESP_LOGI(TAG, "conectando a %s...", WIFI_SSID);
}

bool red_en_linea(void) { return s_en_linea; }

void red_pedir_sincronizacion(void) { s_sync_pedido = true; }

// ============================================================
// 2. HTTP
// ============================================================

// El cuerpo de la respuesta llega a pedazos; se van pegando aquí.
typedef struct {
    char *buf;
    int capacidad;
    int largo;
} respuesta_t;

static esp_err_t recibir_pedazo(esp_http_client_event_t *evt) {
    if (evt->event_id != HTTP_EVENT_ON_DATA) return ESP_OK;

    respuesta_t *r = (respuesta_t *)evt->user_data;
    if (r == NULL) return ESP_OK;

    int espacio = r->capacidad - r->largo - 1;  // -1 para el fin de texto
    if (espacio <= 0) return ESP_OK;

    int copiar = evt->data_len < espacio ? evt->data_len : espacio;
    memcpy(r->buf + r->largo, evt->data, copiar);
    r->largo += copiar;
    r->buf[r->largo] = '\0';
    return ESP_OK;
}

// El servidor va por HTTPS, así que hay que verificar su certificado. En vez
// de llevar el certificado del colegio dentro del firmware (que caduca y
// habría que reflashear cada tres meses), se usa el paquete de autoridades
// raíz que trae ESP-IDF: comprueba la firma igual que un navegador y sigue
// valiendo cuando Let's Encrypt renueve.
//
// Sin esto, cualquiera en la red del colegio podría hacerse pasar por el
// servidor y quedarse con la X-Device-Key, que es la que hace sonar el timbre.

// Devuelve el código HTTP (200, 404...) o -1 si ni siquiera se pudo hablar
// con el servidor.
static int http_get(const char *ruta, char *destino, int capacidad) {
    char url[192];
    snprintf(url, sizeof(url), "%s%s", API_BASE, ruta);

    destino[0] = '\0';
    respuesta_t respuesta = {.buf = destino, .capacidad = capacidad, .largo = 0};

    esp_http_client_config_t cfg = {
        .url = url,
        .timeout_ms = TIEMPO_MAXIMO_MS,
        .event_handler = recibir_pedazo,
        .user_data = &respuesta,
        .crt_bundle_attach = esp_crt_bundle_attach,
    };
    esp_http_client_handle_t cliente = esp_http_client_init(&cfg);
    if (cliente == NULL) return -1;

    esp_http_client_set_header(cliente, "X-Device-Key", DEVICE_API_KEY);
    esp_err_t err = esp_http_client_perform(cliente);
    int codigo = (err == ESP_OK) ? esp_http_client_get_status_code(cliente) : -1;
    esp_http_client_cleanup(cliente);
    return codigo;
}

static int http_post(const char *ruta, const char *cuerpo) {
    char url[192];
    snprintf(url, sizeof(url), "%s%s", API_BASE, ruta);

    esp_http_client_config_t cfg = {
        .url = url,
        .timeout_ms = TIEMPO_MAXIMO_MS,
        .method = HTTP_METHOD_POST,
        .crt_bundle_attach = esp_crt_bundle_attach,
    };
    esp_http_client_handle_t cliente = esp_http_client_init(&cfg);
    if (cliente == NULL) return -1;

    esp_http_client_set_header(cliente, "X-Device-Key", DEVICE_API_KEY);
    esp_http_client_set_header(cliente, "Content-Type", "application/json");
    esp_http_client_set_post_field(cliente, cuerpo, strlen(cuerpo));

    esp_err_t err = esp_http_client_perform(cliente);
    int codigo = (err == ESP_OK) ? esp_http_client_get_status_code(cliente) : -1;
    esp_http_client_cleanup(cliente);
    return codigo;
}

// ============================================================
// 3. Sincronizar el horario (RF-28)
// ============================================================

static void sincronizar_horario(void) {
    char *cuerpo = malloc(TAM_RESPUESTA_HORARIO);
    if (cuerpo == NULL) return;

    int codigo = http_get("/dispositivo/horario", cuerpo, TAM_RESPUESTA_HORARIO);
    if (codigo == 200) {
        horario_aplicar_json(cuerpo, true);
    } else {
        ESP_LOGW(TAG, "sincronización falló (%d); sigo con el horario de la flash", codigo);
    }
    free(cuerpo);
}

// ============================================================
// 4. Órdenes de la app (RNF-04)
// ============================================================
//
// Esta consulta corre periódicamente y reutiliza la conexión HTTP (Keep-Alive)
// para evitar calcular el handshake criptográfico TLS en cada ciclo.

static esp_http_client_handle_t s_cliente_comandos = NULL;

static void consultar_comandos(void) {
    char url[192];
    snprintf(url, sizeof(url), "%s/dispositivo/comandos", API_BASE);
    char cuerpo[512] = {0};
    respuesta_t respuesta = {.buf = cuerpo, .capacidad = sizeof(cuerpo), .largo = 0};

    if (s_cliente_comandos == NULL) {
        esp_http_client_config_t cfg = {
            .url = url,
            .timeout_ms = 4000,
            .event_handler = recibir_pedazo,
            .user_data = &respuesta,
            .crt_bundle_attach = esp_crt_bundle_attach,
            .keep_alive_enable = true,
        };
        s_cliente_comandos = esp_http_client_init(&cfg);
        if (s_cliente_comandos == NULL) return;
        esp_http_client_set_header(s_cliente_comandos, "X-Device-Key", DEVICE_API_KEY);
    } else {
        esp_http_client_set_url(s_cliente_comandos, url);
        esp_http_client_set_user_data(s_cliente_comandos, &respuesta);
    }

    esp_err_t err = esp_http_client_perform(s_cliente_comandos);
    if (err != ESP_OK) {
        esp_http_client_cleanup(s_cliente_comandos);
        s_cliente_comandos = NULL;
        return;
    }
    int codigo = esp_http_client_get_status_code(s_cliente_comandos);
    if (codigo != 200) return;

    cJSON *doc = cJSON_Parse(cuerpo);
    if (doc == NULL) return;

    if (cJSON_IsTrue(cJSON_GetObjectItemCaseSensitive(doc, "timbrar"))) {
        const cJSON *duracion = cJSON_GetObjectItemCaseSensitive(doc, "duracionSeg");
        int segundos = cJSON_IsNumber(duracion) ? (int)duracion->valuedouble : 5;
        timbre_pedir_desde_app((uint8_t)segundos);
    }
    cJSON_Delete(doc);
}

// ============================================================
// 5. Cola de reportes (RF-17 + RF-30)
// ============================================================
//
// Cada evento se escribe primero en `reportes.jsonl` (una línea por evento,
// con su millis()). El envío lee la cola y borra lo enviado; si no hay red, la
// cola simplemente espera. Así el reporte sobrevive a cortes de luz e
// internet, y `ocurridoHaceSeg` viaja calculado con el reloj del módulo.

#if ROL_ESCLAVO

// El esclavo no tiene cola ni servidor a quien mandarla. Suena por horario a la
// misma hora que el maestro, y es el maestro quien lo reporta: si reportaran los
// dos, cada timbre saldría duplicado en la bitácora.

void red_encolar_activacion(const char *tipo, const char *timbre_id, int duracion_seg) {
    (void)tipo;
    (void)timbre_id;
    (void)duracion_seg;
}

void red_encolar_sismo(float intensidad_g, uint32_t duracion_ms, bool confirmado_por_nodo2,
                       float intensidad_nodo2_g) {
    (void)intensidad_g;
    (void)duracion_ms;
    (void)confirmado_por_nodo2;
    (void)intensidad_nodo2_g;
}

#else

static void encolar_linea(const char *linea) {
    xSemaphoreTake(s_candado_cola, portMAX_DELAY);
    FILE *f = fopen(RUTA_COLA, "a");
    if (f != NULL) {
        fputs(linea, f);
        fputc('\n', f);
        fclose(f);
    } else {
        ESP_LOGE(TAG, "no se pudo encolar el reporte");
    }
    xSemaphoreGive(s_candado_cola);

    s_flush_pedido = true;  // con red, la tarea lo manda en el acto
}

static void encolar_documento(cJSON *doc) {
    char *linea = cJSON_PrintUnformatted(doc);
    if (linea != NULL) {
        encolar_linea(linea);
        cJSON_free(linea);
    }
    cJSON_Delete(doc);
}

void red_encolar_activacion(const char *tipo, const char *timbre_id, int duracion_seg) {
    cJSON *doc = cJSON_CreateObject();
    if (doc == NULL) return;
    cJSON_AddStringToObject(doc, "clase", "activacion");
    cJSON_AddNumberToObject(doc, "t", millis());
    cJSON_AddStringToObject(doc, "tipo", tipo);
    if (timbre_id != NULL && timbre_id[0] != '\0') {
        cJSON_AddStringToObject(doc, "horarioTimbreId", timbre_id);
    }
    cJSON_AddNumberToObject(doc, "duracionSeg", duracion_seg);
    encolar_documento(doc);
}

void red_encolar_sismo(float intensidad_g, uint32_t duracion_ms, bool confirmado_por_nodo2,
                       float intensidad_nodo2_g) {
    cJSON *doc = cJSON_CreateObject();
    if (doc == NULL) return;
    cJSON_AddStringToObject(doc, "clase", "sismo");
    cJSON_AddNumberToObject(doc, "t", millis());
    cJSON_AddNumberToObject(doc, "intensidadG", intensidad_g);
    cJSON_AddNumberToObject(doc, "duracionMs", duracion_ms);
    // Campos nuevos: el backend los ignora si todavía no los conoce.
    cJSON_AddBoolToObject(doc, "confirmadoPorNodo2", confirmado_por_nodo2);
    if (confirmado_por_nodo2) {
        cJSON_AddNumberToObject(doc, "intensidadNodo2G", intensidad_nodo2_g);
    }
    encolar_documento(doc);
}

#endif  // ROL_ESCLAVO

// Convierte una línea de la cola en el cuerpo que espera el backend y la
// envía. Devuelve true si el servidor la aceptó.
static bool enviar_linea(const char *linea) {
    cJSON *doc = cJSON_Parse(linea);
    if (doc == NULL) return true;  // línea corrupta: se descarta, no se reintenta

    // Cuánto hace que ocurrió, según el reloj del módulo. Si millis() dio la
    // vuelta (49 días) o el evento es de antes de un reinicio, se manda 0:
    // mejor un tiempo aproximado que perder la bitácora.
    const cJSON *marca = cJSON_GetObjectItemCaseSensitive(doc, "t");
    uint32_t t = cJSON_IsNumber(marca) ? (uint32_t)marca->valuedouble : 0;
    uint32_t hace_ms = (millis() >= t) ? millis() - t : 0;
    cJSON_AddNumberToObject(doc, "ocurridoHaceSeg", hace_ms / 1000);

    const cJSON *clase = cJSON_GetObjectItemCaseSensitive(doc, "clase");
    bool es_sismo = cJSON_IsString(clase) && strcmp(clase->valuestring, "sismo") == 0;
    cJSON_DeleteItemFromObject(doc, "clase");
    cJSON_DeleteItemFromObject(doc, "t");

    char *cuerpo = cJSON_PrintUnformatted(doc);
    cJSON_Delete(doc);
    if (cuerpo == NULL) return true;

    int codigo = http_post(es_sismo ? "/dispositivo/sismos" : "/dispositivo/activaciones", cuerpo);
    cJSON_free(cuerpo);
    return codigo == 201;
}

static void enviar_reportes_pendientes(void) {
    // Primero se aparta la cola con otro nombre. Así el bucle de control puede
    // seguir encolando reportes mientras estos POST tardan lo suyo, sin
    // esperar a que termine el envío.
    xSemaphoreTake(s_candado_cola, portMAX_DELAY);
    struct stat st;
    if (stat(RUTA_ENVIANDO, &st) != 0) {  // sin sobras de un intento anterior
        if (rename(RUTA_COLA, RUTA_ENVIANDO) != 0) {
            xSemaphoreGive(s_candado_cola);
            return;  // no había nada que enviar
        }
    }
    xSemaphoreGive(s_candado_cola);

    FILE *f = fopen(RUTA_ENVIANDO, "r");
    if (f == NULL) return;

    // Lo que no se pueda enviar se vuelve a escribir tal cual, en el mismo
    // orden, y se reintenta en la siguiente vuelta.
    char *pendientes = malloc(2048);
    if (pendientes == NULL) {
        fclose(f);
        return;
    }
    pendientes[0] = '\0';
    size_t largo_pendientes = 0;
    bool hubo_fallo = false;

    char linea[512];
    while (fgets(linea, sizeof(linea), f) != NULL) {
        linea[strcspn(linea, "\r\n")] = '\0';
        if (linea[0] == '\0') continue;

        // Al primer fallo se deja de intentar: si el servidor no está, no
        // tiene sentido machacarlo con el resto de la cola.
        if (!hubo_fallo && enviar_linea(linea)) continue;
        hubo_fallo = true;

        size_t largo = strlen(linea);
        if (largo_pendientes + largo + 2 > 2048) {
            ESP_LOGE(TAG, "la cola de reportes se llenó; se pierden los más nuevos");
            break;
        }
        memcpy(pendientes + largo_pendientes, linea, largo);
        largo_pendientes += largo;
        pendientes[largo_pendientes++] = '\n';
        pendientes[largo_pendientes] = '\0';
    }
    fclose(f);

    if (largo_pendientes == 0) {
        remove(RUTA_ENVIANDO);
    } else {
        FILE *w = fopen(RUTA_ENVIANDO, "w");
        if (w != NULL) {
            fputs(pendientes, w);
            fclose(w);
        }
        ESP_LOGW(TAG, "quedan reportes por enviar");
    }
    free(pendientes);
}

// ============================================================
// 6. La tarea
// ============================================================

void red_tarea(void *argumento) {
    (void)argumento;

    uint32_t t_comando = 0, t_sync = 0, t_flush = 0, t_wifi = 0;
    bool sincronizado_alguna_vez = false;

    while (true) {
        uint32_t ahora = millis();

        if (!s_en_linea) {
            if (s_cliente_comandos != NULL) {
                esp_http_client_cleanup(s_cliente_comandos);
                s_cliente_comandos = NULL;
            }
            if (!s_conectando && ahora - t_wifi >= INTERVALO_WIFI_MS) {
                t_wifi = ahora;
                s_conectando = true;
                esp_wifi_connect();
            }
        } else {
            if (!sincronizado_alguna_vez || s_sync_pedido || ahora - t_sync >= INTERVALO_SYNC_MS) {
                t_sync = ahora;
                s_sync_pedido = false;
                sincronizado_alguna_vez = true;
                sincronizar_horario();
            }
            if (!canal_conectado() && ahora - t_comando >= INTERVALO_COMANDOS_MS) {
                t_comando = ahora;
                consultar_comandos();
            }
            if (s_flush_pedido || ahora - t_flush >= INTERVALO_FLUSH_MS) {
                t_flush = ahora;
                s_flush_pedido = false;
                enviar_reportes_pendientes();
            }
        }

        vTaskDelay(pdMS_TO_TICKS(50));
    }
}
