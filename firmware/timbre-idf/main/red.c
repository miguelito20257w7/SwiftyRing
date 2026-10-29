//
//  red.c
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//

#include "red.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "actualizador_ota.h"
#include "almacen_config.h"
#include "aprovisionamiento.h"
#include "cJSON.h"
#include "comun.h"
#include "config.h"
#include "esp_crt_bundle.h"
#include "esp_event.h"
#include "esp_http_client.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "horario.h"
#include "timbre.h"
#include "canal.h"
#include "pantalla.h"

static const char *TAG = "red";

// La cola de reportes vive en la flash. Mientras se envía, el archivo se
// aparta con otro nombre para no bloquear al resto del firmware.
#define RUTA_COLA RUTA_ALMACEN "/reportes.jsonl"
#define RUTA_ENVIANDO RUTA_ALMACEN "/enviando.jsonl"

#define INTERVALO_COMANDOS_MS 2000              // Respaldo de WS: consulta de comandos cada 2 s
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
static volatile uint32_t s_ultima_sync_exitosa_ms = 0;
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
        canal_desconectar();
        ESP_LOGW(TAG, "sin conexión (motivo: %d)", ev ? ev->reason : -1);
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *evento = (ip_event_got_ip_t *)datos;
        ESP_LOGI(TAG, "conectado, IP " IPSTR, IP2STR(&evento->ip_info.ip));
        s_en_linea = true;
        s_conectando = false;
        // Si este arranque proviene de una actualización OTA, confirmamos éxito al bootloader
        actualizador_ota_confirmar_arranque();
    }
}

void red_iniciar(void) {
    s_candado_cola = xSemaphoreCreateMutex();

    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());

    // Si el módulo no tiene credenciales en NVS, entrar en modo Aprovisionamiento (SoftAP)
    if (!almacen_config_esta_configurado()) {
        ESP_LOGW(TAG, "Módulo sin configurar. Iniciando Setup Wizard local (SoftAP)...");
        aprovisionamiento_iniciar();
        return;
    }

    esp_netif_create_default_wifi_sta();

    wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&init));

    ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID,
                                                        manejar_evento, NULL, NULL));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_GOT_IP,
                                                        manejar_evento, NULL, NULL));

    const char *ssid = almacen_config_wifi_ssid();
    const char *pass = almacen_config_wifi_pass();

    wifi_config_t cfg = {
        .sta = {
            .scan_method = WIFI_ALL_CHANNEL_SCAN,
            .sort_method = WIFI_CONNECT_AP_BY_SIGNAL,
            .ft_enabled = 1,
            .btm_enabled = 1,
            .rm_enabled = 1,
        },
    };
    strlcpy((char *)cfg.sta.ssid, ssid, sizeof(cfg.sta.ssid));
    strlcpy((char *)cfg.sta.password, pass, sizeof(cfg.sta.password));

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &cfg));
    ESP_ERROR_CHECK(esp_wifi_start());

    // Sin ahorro de energía: por defecto la radio se duerme a ratos entre
    // balizas del router, y dormida no oye las tramas de ESP-NOW que le manda
    // el esclavo (enlace.c). Gasta un poco más, pero el módulo está enchufado.
    ESP_ERROR_CHECK(esp_wifi_set_ps(WIFI_PS_NONE));

    ESP_LOGI(TAG, "conectando a %s...", ssid);
}

bool red_en_linea(void) { return s_en_linea; }

static char s_sync_motivo[16] = {0};

void red_pedir_sincronizacion_motivo(const char *motivo) {
    if (motivo != NULL) {
        snprintf(s_sync_motivo, sizeof(s_sync_motivo), "%s", motivo);
    } else {
        s_sync_motivo[0] = '\0';
    }
    s_sync_pedido = true;
}

void red_pedir_sincronizacion(void) {
    red_pedir_sincronizacion_motivo("general");
}

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
    char url[256];
    snprintf(url, sizeof(url), "%s%s", almacen_config_api_base(), ruta);

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

    esp_http_client_set_header(cliente, "X-Device-Key", almacen_config_device_key());
    esp_err_t err = esp_http_client_perform(cliente);
    int codigo = (err == ESP_OK) ? esp_http_client_get_status_code(cliente) : -1;
    esp_http_client_cleanup(cliente);
    return codigo;
}

static int http_post(const char *ruta, const char *cuerpo) {
    char url[256];
    snprintf(url, sizeof(url), "%s%s", almacen_config_api_base(), ruta);

    esp_http_client_config_t cfg = {
        .url = url,
        .timeout_ms = TIEMPO_MAXIMO_MS,
        .method = HTTP_METHOD_POST,
        .crt_bundle_attach = esp_crt_bundle_attach,
    };
    esp_http_client_handle_t cliente = esp_http_client_init(&cfg);
    if (cliente == NULL) return -1;

    esp_http_client_set_header(cliente, "X-Device-Key", almacen_config_device_key());
    esp_http_client_set_header(cliente, "Content-Type", "application/json");
    esp_http_client_set_post_field(cliente, cuerpo, strlen(cuerpo));

    esp_err_t err = esp_http_client_perform(cliente);
    int codigo = (err == ESP_OK) ? esp_http_client_get_status_code(cliente) : -1;
    esp_http_client_cleanup(cliente);
    return codigo;
}

// Canjea un código de autorización temporal (provisto por la app Flutter)
// con el backend para que este le asigne su DEVICE_API_KEY definitiva.
static bool canjear_codigo_con_servidor(void) {
    char url[256];
    snprintf(url, sizeof(url), "%s/dispositivo/canjear-codigo", almacen_config_api_base());

    cJSON *solicitud = cJSON_CreateObject();
    cJSON_AddStringToObject(solicitud, "codigo_autorizacion", almacen_config_auth_code());

    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    char mac_str[18];
    snprintf(mac_str, sizeof(mac_str), "%02X:%02X:%02X:%02X:%02X:%02X",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    cJSON_AddStringToObject(solicitud, "mac", mac_str);

    char *cuerpo_post = cJSON_PrintUnformatted(solicitud);
    cJSON_Delete(solicitud);
    if (!cuerpo_post) return false;

    char respuesta_buf[512] = {0};
    respuesta_t respuesta = {.buf = respuesta_buf, .capacidad = sizeof(respuesta_buf) - 1, .largo = 0};

    esp_http_client_config_t cfg = {
        .url = url,
        .timeout_ms = TIEMPO_MAXIMO_MS,
        .method = HTTP_METHOD_POST,
        .event_handler = recibir_pedazo,
        .user_data = &respuesta,
        .crt_bundle_attach = esp_crt_bundle_attach,
    };
    esp_http_client_handle_t cliente = esp_http_client_init(&cfg);
    if (cliente == NULL) {
        free(cuerpo_post);
        return false;
    }

    esp_http_client_set_header(cliente, "Content-Type", "application/json");
    esp_http_client_set_post_field(cliente, cuerpo_post, strlen(cuerpo_post));

    esp_err_t err = esp_http_client_perform(cliente);
    int codigo = (err == ESP_OK) ? esp_http_client_get_status_code(cliente) : -1;
    esp_http_client_cleanup(cliente);
    free(cuerpo_post);

    if (codigo != 200) {
        ESP_LOGE(TAG, "Canje de código falló con código HTTP %d. Resp: %s", codigo, respuesta_buf);
        return false;
    }

    cJSON *resp_json = cJSON_Parse(respuesta_buf);
    if (!resp_json) return false;

    cJSON *j_key = cJSON_GetObjectItem(resp_json, "device_api_key");
    if (!cJSON_IsString(j_key) || strlen(j_key->valuestring) == 0) {
        cJSON_Delete(resp_json);
        return false;
    }

    almacen_config_guardar_device_key(j_key->valuestring);
    cJSON_Delete(resp_json);
    return true;
}

// ============================================================
// 3. Sincronizar el horario (RF-28)
// ============================================================

static void sincronizar_horario(void) {
    char *cuerpo = malloc(TAM_RESPUESTA_HORARIO);
    if (cuerpo == NULL) return;

    int codigo = http_get("/dispositivo/horario", cuerpo, TAM_RESPUESTA_HORARIO);
    if (codigo == 200) {
        s_ultima_sync_exitosa_ms = millis();
        horario_aplicar_json(cuerpo, true);
        if (strcmp(s_sync_motivo, "especial") == 0) {
            pantalla_notificar_cambio("HORARIO ESPECIAL", "ACTUALIZADO");
        } else if (strcmp(s_sync_motivo, "horario") == 0) {
            pantalla_notificar_cambio("HORARIOS", "ACTUALIZADO");
        } else if (strcmp(s_sync_motivo, "general") == 0) {
            pantalla_notificar_cambio("HORARIOS", "ACTUALIZADO");
        }
        // "inicio" o sincronización periódica de fondo no emiten popup molesto
    } else {
        ESP_LOGW(TAG, "sincronización falló (%d); sigo con el horario de la flash", codigo);
    }
    s_sync_motivo[0] = '\0';
    free(cuerpo);
}

uint32_t red_tiempo_desde_sync(void) {
    if (s_ultima_sync_exitosa_ms == 0) return UINT32_MAX;
    return millis() - s_ultima_sync_exitosa_ms;
}

// ============================================================
// 4. Órdenes de la app (RNF-04)
// ============================================================
//
// Esta consulta corre periódicamente y reutiliza la conexión HTTP (Keep-Alive)
// para evitar calcular el handshake criptográfico TLS en cada ciclo.

static esp_http_client_handle_t s_cliente_comandos = NULL;

static void consultar_comandos(void) {
    char url[256];
    snprintf(url, sizeof(url), "%s/dispositivo/comandos", almacen_config_api_base());
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
        esp_http_client_set_header(s_cliente_comandos, "X-Device-Key", almacen_config_device_key());
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

    int cambios_cfg = 0;
    char cfg_tit[24] = {0};
    char cfg_det[32] = {0};

    const cJSON *ups = cJSON_GetObjectItemCaseSensitive(doc, "modoUps");
    if (cJSON_IsBool(ups)) {
        bool nuevo_ups = cJSON_IsTrue(ups);
        if (nuevo_ups != timbre_modo_ups()) {
            timbre_fijar_modo_ups(nuevo_ups);
            cambios_cfg++;
            snprintf(cfg_tit, sizeof(cfg_tit), "MODO UPS");
            snprintf(cfg_det, sizeof(cfg_det), "%s", nuevo_ups ? "ACTIVADO" : "DESACTIVADO");
            ESP_LOGI(TAG, "modo UPS actualizado (polling): %s", nuevo_ups ? "ON" : "OFF");
        }
    }

    const cJSON *dur_man = cJSON_GetObjectItemCaseSensitive(doc, "duracionTimbreManualSeg");
    if (cJSON_IsNumber(dur_man)) {
        uint8_t nuevo_dur = (uint8_t)dur_man->valuedouble;
        if (nuevo_dur != timbre_duracion_manual()) {
            timbre_fijar_duracion_manual(nuevo_dur);
            cambios_cfg++;
            snprintf(cfg_tit, sizeof(cfg_tit), "DURACION TIMBRE");
            snprintf(cfg_det, sizeof(cfg_det), "%d seg", nuevo_dur);
            ESP_LOGI(TAG, "duracion manual actualizada (polling): %d seg", nuevo_dur);
        }
    }

    if (cambios_cfg > 1) {
        pantalla_notificar_cambio("CONFIGURACION", "ACTUALIZADA");
    } else if (cambios_cfg == 1) {
        pantalla_notificar_cambio(cfg_tit, cfg_det);
    }

    if (cJSON_IsTrue(cJSON_GetObjectItemCaseSensitive(doc, "sincronizar"))) {
        pantalla_notificar_cambio("HORARIOS", "ACTUALIZANDO...");
        red_pedir_sincronizacion_motivo("horario");
    }

    if (cJSON_IsTrue(cJSON_GetObjectItemCaseSensitive(doc, "reset"))) {
        ESP_LOGW(TAG, "Orden de restablecimiento de fábrica recibida desde el backend");
        pantalla_mensaje("RESTABLECIENDO", "DE FABRICA...");
        almacen_config_restablecer_fabrica();
        vTaskDelay(pdMS_TO_TICKS(1500));
        esp_restart();
    }

    const cJSON *j_ota = cJSON_GetObjectItemCaseSensitive(doc, "otaUrl");
    if (cJSON_IsString(j_ota) && strlen(j_ota->valuestring) > 0) {
        ESP_LOGW(TAG, "Orden de actualización OTA recibida: %s", j_ota->valuestring);
        actualizador_ota_iniciar(j_ota->valuestring);
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
        // Si el módulo está en Modo Setup (SoftAP) o actualizando por OTA, no intentar conexiones
        if (aprovisionamiento_activo() || actualizador_ota_en_curso()) {
            vTaskDelay(pdMS_TO_TICKS(500));
            continue;
        }

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
            if (!sincronizado_alguna_vez) {
                // Si el módulo físico tiene un código de autorización pendiente para obtener su clave
                if (almacen_config_tiene_auth_code() && !almacen_config_tiene_device_key()) {
                    ESP_LOGI(TAG, "Canjeando código de autorización con el backend...");
                    pantalla_mensaje("AUTORIZANDO", "PIDIENDO CLAVE...");
                    if (!canjear_codigo_con_servidor()) {
                        ESP_LOGE(TAG, "Código de autorización inválido o rechazado");
                        pantalla_mensaje("ERROR CODIGO", "RESTAURANDO SETUP");
                        vTaskDelay(pdMS_TO_TICKS(4000));
                        almacen_config_restablecer_fabrica();
                        esp_restart();
                        return;
                    }
                    pantalla_mensaje("AUTORIZADO", "CLAVE ASIGNADA");
                    vTaskDelay(pdMS_TO_TICKS(1500));
                }

                // Al conectar WiFi, primero sincronizamos el horario por HTTP de forma secuencial.
                // Luego damos un respiro a la CPU (FreeRTOS IDLE task resetea el watchdog)
                // y conectamos el WebSocket. Nunca ambos a la vez para no colapsar la CPU con
                // dos negociaciones TLS en paralelo en el ESP32-C3.
                sincronizado_alguna_vez = true;
                t_sync = ahora;
                s_sync_pedido = false;
                sincronizar_horario();
                vTaskDelay(pdMS_TO_TICKS(150));
                canal_conectar();
            } else {
                canal_conectar();

                if (s_sync_pedido || ahora - t_sync >= INTERVALO_SYNC_MS) {
                    t_sync = ahora;
                    s_sync_pedido = false;
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
        }

        vTaskDelay(pdMS_TO_TICKS(50));
    }
}
