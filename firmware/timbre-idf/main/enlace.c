//
//  enlace.c
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//

#include "enlace.h"

#include <string.h>

#include "comun.h"
#include "config.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_now.h"
#include "esp_random.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "horario.h"
#include "red.h"
#include "reloj.h"
#include "sismo.h"
#include "timbre.h"

static const char *TAG = "enlace";

// ============================================================
// 1. Las tramas
// ============================================================
//
// Por ESP-NOW caben 250 bytes por trama y no hay reintentos ni orden
// garantizado: cada trama tiene que valerse por sí sola. Todas empiezan por la
// misma cabecera y detrás va la carga, que depende del tipo.

#define ENLACE_VERSION 1

typedef enum {
    TRAMA_LATIDO = 1,     // maestro → todos: "aquí estoy", la hora y qué horario tengo
    TRAMA_ESTADO = 2,     // esclavo → maestro: "sigo vivo" y qué horario tengo
    TRAMA_CABECERA = 3,   // maestro → esclavo: metadatos del horario que va a mandar
    TRAMA_PARTE = 4,      // maestro → esclavo: un puñado de timbres
    TRAMA_SACUDIDA = 5,   // los dos: "mi acelerómetro sintió esto"
    TRAMA_ALARMA = 6,     // maestro → esclavo: "timbra ya" (botón físico u orden de la app)
} tipo_trama_t;

typedef struct __attribute__((packed)) {
    uint8_t version;    // ENLACE_VERSION; si no coincide, la trama se tira
    uint8_t tipo;       // tipo_trama_t
    uint8_t relleno[2];
    uint32_t sesion;    // número al azar, distinto en cada arranque
    uint32_t contador;  // sube en cada trama de esta sesión
    uint32_t firma;     // depende del contenido y de la clave compartida
} cabecera_t;

typedef struct __attribute__((packed)) {
    uint32_t hora_unix;        // la hora del maestro, en segundos UTC
    uint32_t version_horario;
    uint8_t timbre_activo;
    uint8_t en_linea;          // el maestro tiene internet
} carga_latido_t;

typedef struct __attribute__((packed)) {
    uint32_t version_horario;  // la que tiene el esclavo ahora mismo
    uint8_t timbre_activo;
    uint8_t hora_valida;
} carga_estado_t;

#define TIMBRES_POR_PARTE 8

typedef struct __attribute__((packed)) {
    uint32_t version;
    uint8_t total_partes;
    uint8_t cant_habitual;
    uint8_t cant_especial;
    uint8_t hay_especial;
    float umbral_sismico_g;
    uint16_t sismo_duracion_min_ms;
    char especial_nombre[33];
    char especial_inicio[11];
    char especial_fin[11];
} carga_cabecera_t;

typedef struct __attribute__((packed)) {
    uint32_t version;
    uint8_t parte;     // 0..total_partes-1
    uint8_t cantidad;  // timbres útiles en esta trama
    uint8_t relleno[2];
    timbre_compacto_t timbres[TIMBRES_POR_PARTE];
} carga_parte_t;

typedef struct __attribute__((packed)) {
    float pico_g;
    uint32_t duracion_ms;
} carga_sacudida_t;

typedef struct __attribute__((packed)) {
    uint8_t duracion_seg;
    char motivo[21];
} carga_alarma_t;

// Una trama entera, tal como viaja y tal como se guarda en la cola.
typedef struct {
    cabecera_t cabecera;
    union {
        carga_latido_t latido;
        carga_estado_t estado;
        carga_cabecera_t horario;
        carga_parte_t parte;
        carga_sacudida_t sacudida;
        carga_alarma_t alarma;
        uint8_t bytes[ESP_NOW_MAX_DATA_LEN - sizeof(cabecera_t)];
    } carga;
} trama_t;

_Static_assert(sizeof(carga_parte_t) + sizeof(cabecera_t) <= ESP_NOW_MAX_DATA_LEN,
               "la trama del horario no cabe en un paquete de ESP-NOW");

// ============================================================
// 2. Ritmos
// ============================================================

// El latido va rápido mientras no hay pareja: es lo que el esclavo va buscando
// canal por canal, y cuanto más seguido lo mande, antes lo encuentra.
#define LATIDO_BUSCANDO_MS 250
#define LATIDO_MS 1000
#define ESTADO_MS 2000

// Sin oír al otro durante este tiempo se le da por perdido. Da margen para
// perder tres o cuatro tramas seguidas: darlo por muerto de más significa que
// el detector de sismos deja de exigir confirmación y vuelven las falsas
// alarmas, así que conviene ser paciente.
#define SILENCIO_MAXIMO_MS 8000

// Algunas tramas no se pueden perder — el aviso de sacudida y la orden de
// timbrar — y ESP-NOW no reintenta por su cuenta. Se mandan tres veces
// espaciadas, para que una interferencia corta no se las lleve. Que lleguen
// repetidas no hace daño: las tres dicen lo mismo.
#define REPETICIONES 2
#define REPETIR_MS 200

// Cuánto se queda el esclavo en cada canal mientras busca. Tiene que ser más
// que LATIDO_BUSCANDO_MS o pasaría de largo justo entre dos latidos.
#define SALTO_CANAL_MS 400
#define CANAL_MAXIMO 13

// Entre trama y trama del horario, para no atragantar la radio.
#define ENVIO_PARTE_MS 100

// Si el horario se queda a medias (se perdió una trama), se vuelve a mandar
// entero pasado este tiempo.
#define REINTENTO_HORARIO_MS 10000

static const uint8_t DIFUSION[ESP_NOW_ETH_ALEN] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

// ============================================================
// 3. Estado
// ============================================================

static QueueHandle_t s_recibidas;  // lo que llega por la radio, para el bucle de control
static uint32_t s_sesion = 0;
static uint32_t s_contador = 0;

// El sistema es de DOS módulos: cada uno tiene una sola pareja. Si algún día
// hubiera un tercero, este estado tendría que volverse un arreglo.
static uint8_t s_pareja[ESP_NOW_ETH_ALEN];
static bool s_pareja_conocida = false;
static uint32_t s_ultima_noticia = 0;
static bool s_hubo_noticia = false;

static uint32_t s_sesion_pareja = 0;
static uint32_t s_contador_pareja = 0;
static bool s_sesion_pareja_conocida = false;

#if ROL_ESCLAVO
static uint8_t s_canal = 1;
static uint32_t s_ultimo_salto = 0;
static uint32_t s_version_recibida = 0;   // la del horario que se está armando
static uint16_t s_partes_pendientes = 0;  // un bit por parte que falta
static uint32_t s_inicio_armado = 0;
static carga_cabecera_t s_cabecera_recibida;
static timbre_compacto_t s_armando[MAX_TIMBRES_TOTAL];
#else
static uint32_t s_ultimo_latido = 0;
static uint32_t s_version_enviando = 0;
static uint8_t s_parte_a_enviar = 0;
static uint8_t s_total_partes = 0;
static uint32_t s_ultimo_envio_parte = 0;
static uint32_t s_ultimo_intento_horario = 0;
#endif

// ============================================================
// 4. Firma
// ============================================================
//
// ESP-NOW no cifra las tramas de difusión, así que sin nada más cualquiera con
// un ESP32 en el parqueadero podría mandar un "timbra ya" o fingir un sismo.
//
// La defensa es sencilla: cada trama lleva una firma calculada sobre su
// contenido MÁS una clave que solo conocen los dos módulos (ENLACE_CLAVE, que
// vive en config.h y no se sube a git). Quien no tenga la clave no puede
// calcular la firma, y quien cambie un byte de la trama la invalida.
//
// Contra la repetición (grabar un "timbra ya" y reproducirlo mil veces) va el
// contador: cada trama lleva uno mayor que el anterior y las repetidas se
// tiran. El `sesion` es lo que permite que, cuando el otro módulo se reinicia y
// su contador vuelve a empezar, sus tramas no queden rechazadas para siempre.
//
// No es criptografía de verdad — para eso ESP-NOW tiene cifrado con LMK, que
// sería el siguiente paso — pero corta en seco el ataque que está al alcance de
// cualquiera.

static uint32_t firmar(const trama_t *trama, size_t largo_carga) {
    cabecera_t copia = trama->cabecera;
    copia.firma = 0;  // la firma no se firma a sí misma

    uint32_t h = 2166136261u;
    const uint8_t *p = (const uint8_t *)&copia;
    for (size_t i = 0; i < sizeof(copia); i++) {
        h ^= p[i];
        h *= 16777619u;
    }
    p = (const uint8_t *)&trama->carga;
    for (size_t i = 0; i < largo_carga; i++) {
        h ^= p[i];
        h *= 16777619u;
    }
    for (const char *k = ENLACE_CLAVE; *k != '\0'; k++) {
        h ^= (uint8_t)*k;
        h *= 16777619u;
    }
    return h;
}

// ============================================================
// 5. Enviar
// ============================================================

static void enviar(uint8_t tipo, const void *carga, size_t largo_carga, const uint8_t *destino) {
    if (largo_carga > sizeof(((trama_t *)0)->carga)) return;

    trama_t trama = {0};
    trama.cabecera.version = ENLACE_VERSION;
    trama.cabecera.tipo = tipo;
    trama.cabecera.sesion = s_sesion;
    trama.cabecera.contador = ++s_contador;
    if (carga != NULL && largo_carga > 0) memcpy(&trama.carga, carga, largo_carga);
    trama.cabecera.firma = firmar(&trama, largo_carga);

    esp_err_t err = esp_now_send(destino, (const uint8_t *)&trama, sizeof(cabecera_t) + largo_carga);
    if (err != ESP_OK) ESP_LOGD(TAG, "no salió la trama %u (%s)", tipo, esp_err_to_name(err));
}

// La última trama de las que no se pueden perder, guardada para repetirla. Solo
// cabe una en curso: si llegara otra antes de terminar, la nueva manda (y la
// vieja ya salió al menos una vez).
static struct {
    uint8_t tipo;
    uint8_t destino[ESP_NOW_ETH_ALEN];
    uint8_t carga[32];
    size_t largo;
    uint8_t quedan;
    uint32_t ultimo;
} s_insistente;

static void enviar_insistiendo(uint8_t tipo, const void *carga, size_t largo,
                               const uint8_t *destino) {
    enviar(tipo, carga, largo, destino);
    if (largo > sizeof(s_insistente.carga)) return;

    s_insistente.tipo = tipo;
    memcpy(s_insistente.destino, destino, ESP_NOW_ETH_ALEN);
    memcpy(s_insistente.carga, carga, largo);
    s_insistente.largo = largo;
    s_insistente.quedan = REPETICIONES;
    s_insistente.ultimo = millis();
}

static void repetir_pendiente(uint32_t ahora) {
    if (s_insistente.quedan == 0 || ahora - s_insistente.ultimo < REPETIR_MS) return;
    s_insistente.quedan--;
    s_insistente.ultimo = ahora;
    enviar(s_insistente.tipo, s_insistente.carga, s_insistente.largo, s_insistente.destino);
}

static void asegurar_peer(const uint8_t *mac) {
    if (esp_now_is_peer_exist(mac)) return;
    esp_now_peer_info_t peer = {0};
    memcpy(peer.peer_addr, mac, ESP_NOW_ETH_ALEN);
    peer.channel = 0;  // 0 = el canal en el que ya está la radio
    peer.ifidx = WIFI_IF_STA;
    peer.encrypt = false;
    esp_now_add_peer(&peer);

#if ROL_ESCLAVO
    // Las tramas a este destino salen en Long Range en el esclavo
    esp_now_rate_config_t velocidad = {
        .phymode = WIFI_PHY_MODE_LR,
        .rate = WIFI_PHY_RATE_LORA_250K,
        .ersu = false,
        .dcm = false,
    };
    esp_err_t err = esp_now_set_peer_rate_config(mac, &velocidad);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "sin largo alcance hacia %02x:%02x:%02x:%02x:%02x:%02x (%s)", mac[0], mac[1],
                 mac[2], mac[3], mac[4], mac[5], esp_err_to_name(err));
    }
#endif
}

// ============================================================
// 6. Recibir (esto corre en la tarea del WiFi)
// ============================================================
//
// Aquí NO se toca el relé ni la flash: la trama se copia a la cola y el trabajo
// de verdad lo hace enlace_atender() desde el bucle de control, que es la única
// tarea que acciona el timbre.

static void al_recibir(const esp_now_recv_info_t *info, const uint8_t *datos, int largo) {
    if (largo < (int)sizeof(cabecera_t) || largo > (int)sizeof(trama_t)) return;

    trama_t trama = {0};
    memcpy(&trama, datos, largo);
    if (trama.cabecera.version != ENLACE_VERSION) return;

    size_t largo_carga = largo - sizeof(cabecera_t);
    if (trama.cabecera.firma != firmar(&trama, largo_carga)) {
        ESP_LOGW(TAG, "trama con firma que no cuadra; se tira");
        return;
    }

    // Repetida o vieja: se tira. Cuando la sesión cambia es que el otro módulo
    // se reinició, y su contador vuelve a empezar legítimamente.
    if (s_sesion_pareja_conocida && trama.cabecera.sesion == s_sesion_pareja &&
        trama.cabecera.contador <= s_contador_pareja) {
        return;
    }
    s_sesion_pareja = trama.cabecera.sesion;
    s_contador_pareja = trama.cabecera.contador;
    s_sesion_pareja_conocida = true;

    memcpy(s_pareja, info->src_addr, ESP_NOW_ETH_ALEN);
    s_pareja_conocida = true;
    s_ultima_noticia = millis();
    s_hubo_noticia = true;

    // Si la cola se llena se pierde la trama más nueva: es preferible a
    // bloquear la tarea del WiFi.
    xQueueSend(s_recibidas, &trama, 0);
}

// ============================================================
// 7. Arranque
// ============================================================

#if ROL_ESCLAVO
// El esclavo enciende la radio pero NO se conecta a ninguna red: ESP-NOW no la
// necesita. Lo único que le hace falta es estar en el mismo canal que el
// maestro, y eso lo resuelve buscándolo en enlace_atender().
static void encender_radio_sin_red(void) {
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());

    wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&init));
    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_start());
    ESP_ERROR_CHECK(esp_wifi_set_ps(WIFI_PS_NONE));
}
#endif

// Los dos módulos están en edificios distintos, así que el alcance es lo que
// decide si esto funciona. Dos ajustes, los dos gratis:
//
//  · Modo Long Range (LR): un modo propietario de Espressif que manda a 250
//    kbps con una modulación mucho más robusta que la normal. Al ir más lento,
//    el receptor puede rescatar la señal de mucho más ruido — se ganan unos
//    10 dB de sensibilidad, que en la práctica es entre el doble y el cuádruple
//    de distancia. Aquí no cuesta nada: las tramas son de 250 bytes como mucho
//    y va una por segundo.
//
//    Ojo con el detalle importante: el LR se AÑADE a los protocolos normales,
//    no los reemplaza. Así el maestro puede seguir hablando con el router del
//    colegio, que no entiende LR, y el LR se usa solo entre los dos módulos,
//    que sí. Si se dejara LR a secas, el maestro se quedaría sin internet.
//
//  · Potencia de transmisión al máximo que permite la ley (20 dBm). El chip
//    arranca un poco por debajo; la ganancia es pequeña, pero es de regalo.
static void configurar_alcance(void) {
#if ROL_ESCLAVO
    esp_err_t err = esp_wifi_set_protocol(WIFI_IF_STA, WIFI_PROTOCOL_11B | WIFI_PROTOCOL_11G |
                                                           WIFI_PROTOCOL_11N | WIFI_PROTOCOL_LR);
#else
    // En el maestro, NO activar WIFI_PROTOCOL_LR en la interfaz STA: los routers Mesh
    // como TP-Link Deco M4 detectan IEs propietarias de tasa extendida y rechazan la autenticación (2, 4, 202).
    esp_err_t err = esp_wifi_set_protocol(WIFI_IF_STA, WIFI_PROTOCOL_11B | WIFI_PROTOCOL_11G |
                                                           WIFI_PROTOCOL_11N);
#endif
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "el modo de radio no se activó (%s); sigo con el normal",
                 esp_err_to_name(err));
    }

    // 78 representa 19.5 dBm (evita picos de corriente que saturan el regulador del ESP32-C3)
    esp_wifi_set_max_tx_power(78);
}

void enlace_iniciar(void) {
    s_recibidas = xQueueCreate(8, sizeof(trama_t));
    if (s_recibidas == NULL) {
        ESP_LOGE(TAG, "sin memoria para la cola del enlace");
        return;
    }
    s_sesion = esp_random();

#if ROL_ESCLAVO
    encender_radio_sin_red();
#endif

    configurar_alcance();  // antes de dar de alta destinos: la velocidad va por destino

    ESP_ERROR_CHECK(esp_now_init());
    ESP_ERROR_CHECK(esp_now_register_recv_cb(al_recibir));
    asegurar_peer(DIFUSION);

    uint8_t mac[ESP_NOW_ETH_ALEN] = {0};
    esp_wifi_get_mac(WIFI_IF_STA, mac);
    ESP_LOGI(TAG, "ESP-NOW listo como %s · MAC %02x:%02x:%02x:%02x:%02x:%02x",
             ROL_ESCLAVO ? "esclavo" : "maestro", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

bool enlace_pareja_viva(void) {
    return s_hubo_noticia && (millis() - s_ultima_noticia) < SILENCIO_MAXIMO_MS;
}

// ============================================================
// 8. Lo que manda cada rol
// ============================================================

void enlace_avisar_sacudida(float pico_g, uint32_t duracion_ms) {
    // Va por difusión a propósito: es urgente y no puede depender de que la
    // dirección del otro módulo ya se conozca.
    carga_sacudida_t carga = {.pico_g = pico_g, .duracion_ms = duracion_ms};
    enviar_insistiendo(TRAMA_SACUDIDA, &carga, sizeof(carga), DIFUSION);
}

void enlace_ordenar_alarma(uint8_t duracion_seg, const char *motivo) {
#if !ROL_ESCLAVO
    if (!s_pareja_conocida) return;
    carga_alarma_t carga = {.duracion_seg = duracion_seg};
    strlcpy(carga.motivo, motivo != NULL ? motivo : "", sizeof(carga.motivo));
    enviar_insistiendo(TRAMA_ALARMA, &carga, sizeof(carga), s_pareja);
#else
    (void)duracion_seg;
    (void)motivo;
#endif
}

#if !ROL_ESCLAVO

// El maestro empuja el horario en varias tramas: primero la cabecera con los
// metadatos y cuántas partes vienen, y detrás las partes con los timbres.
static void empezar_envio_horario(void) {
    horario_resumen_t resumen;
    horario_resumen(&resumen);

    uint16_t total = resumen.cant_habitual + resumen.cant_especial;
    s_total_partes = (uint8_t)((total + TIMBRES_POR_PARTE - 1) / TIMBRES_POR_PARTE);
    // Un horario vacío también hay que mandarlo (por ejemplo, cuando se borran
    // todos los timbres): va en una trama sin timbres dentro.
    if (s_total_partes == 0) s_total_partes = 1;
    s_version_enviando = resumen.version;
    s_parte_a_enviar = 0;
    s_ultimo_envio_parte = millis();
    s_ultimo_intento_horario = millis();

    carga_cabecera_t carga = {
        .version = resumen.version,
        .total_partes = s_total_partes,
        .cant_habitual = resumen.cant_habitual,
        .cant_especial = resumen.cant_especial,
        .hay_especial = resumen.hay_especial ? 1 : 0,
        .umbral_sismico_g = resumen.umbral_sismico_g,
        .sismo_duracion_min_ms = resumen.sismo_duracion_min_ms,
    };
    strlcpy(carga.especial_nombre, resumen.especial_nombre, sizeof(carga.especial_nombre));
    strlcpy(carga.especial_inicio, resumen.especial_inicio, sizeof(carga.especial_inicio));
    strlcpy(carga.especial_fin, resumen.especial_fin, sizeof(carga.especial_fin));

    enviar(TRAMA_CABECERA, &carga, sizeof(carga), s_pareja);
    ESP_LOGI(TAG, "mandando el horario al esclavo: %u timbres en %u tramas", total, s_total_partes);
}

static void enviar_siguiente_parte(void) {
    // Si el horario cambió a mitad del envío (justo llegó una sincronización
    // del servidor), las tramas que faltan llevarían timbres nuevos con el
    // número de versión viejo. Se corta y se empieza de cero.
    if (horario_version() != s_version_enviando) {
        ESP_LOGI(TAG, "el horario cambió a mitad del envío; se manda otra vez");
        empezar_envio_horario();
        return;
    }

    carga_parte_t carga = {.version = s_version_enviando, .parte = s_parte_a_enviar};
    carga.cantidad = horario_exportar((uint16_t)(s_parte_a_enviar * TIMBRES_POR_PARTE),
                                      carga.timbres, TIMBRES_POR_PARTE);
    enviar(TRAMA_PARTE, &carga, sizeof(carga), s_pareja);

    s_parte_a_enviar++;
    s_ultimo_envio_parte = millis();
}

static void tareas_del_maestro(uint32_t ahora) {
    uint32_t cada = enlace_pareja_viva() ? LATIDO_MS : LATIDO_BUSCANDO_MS;
    if (ahora - s_ultimo_latido >= cada) {
        s_ultimo_latido = ahora;

        time_t epoca;
        time(&epoca);
        carga_latido_t carga = {
            .hora_unix = (uint32_t)epoca,
            .version_horario = horario_version(),
            .timbre_activo = timbre_activo() ? 1 : 0,
            .en_linea = red_en_linea() ? 1 : 0,
        };
        enviar(TRAMA_LATIDO, &carga, sizeof(carga), DIFUSION);
    }

    // Las partes del horario salen espaciadas para no atragantar la radio.
    if (s_parte_a_enviar < s_total_partes && ahora - s_ultimo_envio_parte >= ENVIO_PARTE_MS) {
        enviar_siguiente_parte();
    }
}

#else

static void tareas_del_esclavo(uint32_t ahora) {
    // ---- Buscar al maestro ----
    //
    // ESP-NOW solo funciona si los dos están en el mismo canal, y el canal del
    // maestro lo decide el router del colegio. Como el esclavo está fuera del
    // alcance de ese router, no puede preguntárselo: se pone a saltar de canal
    // en canal hasta que oye un latido, y ahí se queda.
    if (!enlace_pareja_viva()) {
        if (ahora - s_ultimo_salto >= SALTO_CANAL_MS) {
            s_ultimo_salto = ahora;
            s_canal = (uint8_t)(s_canal % CANAL_MAXIMO) + 1;
            esp_wifi_set_channel(s_canal, WIFI_SECOND_CHAN_NONE);  // el canal 13 no vale en todos
        }                                                          // los países: si falla, se salta
        return;  // sin maestro no hay nada más que mandar
    }

    // ---- Contarle al maestro qué horario tengo ----
    //
    // No hace falta pedirle nada: con saber qué versión tengo, el maestro
    // decide si me manda el horario nuevo.
    static uint32_t ultimo_estado = 0;
    if (ultimo_estado == 0 || ahora - ultimo_estado >= ESTADO_MS) {
        ultimo_estado = ahora;
        carga_estado_t carga = {
            .version_horario = horario_version(),
            .timbre_activo = timbre_activo() ? 1 : 0,
            .hora_valida = reloj_valida() ? 1 : 0,
        };
        enviar(TRAMA_ESTADO, &carga, sizeof(carga), s_pareja);
    }

    // Si el horario se quedó a medias porque se perdió una trama, se olvida lo
    // recibido: el maestro lo volverá a mandar entero al ver la versión vieja.
    if (s_partes_pendientes != 0 && ahora - s_inicio_armado > REINTENTO_HORARIO_MS) {
        ESP_LOGW(TAG, "el horario llegó incompleto; se pedirá de nuevo");
        s_partes_pendientes = 0;
        s_version_recibida = 0;
    }
}

// Junta las partes del horario; cuando están todas, lo aplica y lo guarda.
static void armar_horario(const carga_parte_t *parte) {
    if (parte->version != s_version_recibida || s_partes_pendientes == 0) return;
    if (parte->parte >= s_cabecera_recibida.total_partes) return;
    if (parte->cantidad > TIMBRES_POR_PARTE) return;

    uint16_t desde = (uint16_t)parte->parte * TIMBRES_POR_PARTE;
    if (desde + parte->cantidad > MAX_TIMBRES_TOTAL) return;
    memcpy(&s_armando[desde], parte->timbres, parte->cantidad * sizeof(timbre_compacto_t));

    s_partes_pendientes &= (uint16_t) ~(1u << parte->parte);
    if (s_partes_pendientes != 0) return;  // todavía faltan tramas

    horario_resumen_t resumen = {
        .version = s_cabecera_recibida.version,
        .cant_habitual = s_cabecera_recibida.cant_habitual,
        .cant_especial = s_cabecera_recibida.cant_especial,
        .hay_especial = s_cabecera_recibida.hay_especial != 0,
        .umbral_sismico_g = s_cabecera_recibida.umbral_sismico_g,
        .sismo_duracion_min_ms = s_cabecera_recibida.sismo_duracion_min_ms,
    };
    strlcpy(resumen.especial_nombre, s_cabecera_recibida.especial_nombre,
            sizeof(resumen.especial_nombre));
    strlcpy(resumen.especial_inicio, s_cabecera_recibida.especial_inicio,
            sizeof(resumen.especial_inicio));
    strlcpy(resumen.especial_fin, s_cabecera_recibida.especial_fin, sizeof(resumen.especial_fin));

    horario_aplicar_binario(&resumen, s_armando,
                            (uint16_t)(resumen.cant_habitual + resumen.cant_especial));
    s_version_recibida = 0;
}

#endif  // ROL_ESCLAVO

// ============================================================
// 9. Atender lo recibido
// ============================================================

static void atender_trama(const trama_t *trama) {
    switch (trama->cabecera.tipo) {
#if ROL_ESCLAVO
        case TRAMA_LATIDO: {
            const carga_latido_t *l = &trama->carga.latido;
            // El esclavo no tiene internet ni NTP: su hora es la del maestro.
            // Solo se toca el reloj si está mal o si se ha ido de más de 5 s,
            // para no estar moviéndolo cada segundo.
            reloj_fijar_epoca((time_t)l->hora_unix, 5);
            break;
        }

        case TRAMA_CABECERA: {
            const carga_cabecera_t *c = &trama->carga.horario;
            if (c->version == horario_version() && horario_version() != 0) break;
            if (c->total_partes == 0 || c->total_partes > 16) break;

            s_cabecera_recibida = *c;
            // Los textos llegan de fuera: si vinieran llenos hasta el último
            // byte no tendrían fin de cadena, y leerlos se saldría del struct.
            s_cabecera_recibida.especial_nombre[sizeof(s_cabecera_recibida.especial_nombre) - 1] = '\0';
            s_cabecera_recibida.especial_inicio[sizeof(s_cabecera_recibida.especial_inicio) - 1] = '\0';
            s_cabecera_recibida.especial_fin[sizeof(s_cabecera_recibida.especial_fin) - 1] = '\0';

            s_version_recibida = c->version;
            s_partes_pendientes = (uint16_t)((1u << c->total_partes) - 1u);
            s_inicio_armado = millis();
            memset(s_armando, 0, sizeof(s_armando));
            break;
        }

        case TRAMA_PARTE:
            armar_horario(&trama->carga.parte);
            break;

        case TRAMA_ALARMA: {
            const carga_alarma_t *a = &trama->carga.alarma;
            char motivo[sizeof(a->motivo)];
            strlcpy(motivo, a->motivo, sizeof(motivo));
            ESP_LOGI(TAG, "el maestro ordena timbrar (%s)", motivo);
            timbre_activar(a->duracion_seg, motivo[0] != '\0' ? motivo : "Maestro");
            break;
        }
#else
        case TRAMA_ESTADO: {
            const carga_estado_t *e = &trama->carga.estado;
            // El esclavo dice qué horario tiene: si no es el de ahora, se le
            // manda el nuevo. El reintento espaciado evita volver a empezar el
            // envío mientras el anterior todavía va en camino.
            if (e->version_horario != horario_version() && horario_version() != 0 &&
                millis() - s_ultimo_intento_horario > REINTENTO_HORARIO_MS) {
                empezar_envio_horario();
            }
            break;
        }
#endif

        case TRAMA_SACUDIDA: {
            const carga_sacudida_t *s = &trama->carga.sacudida;
            sismo_sacudida_remota(s->pico_g, s->duracion_ms);
            break;
        }

        default:
            break;
    }
}

void enlace_atender(void) {
    if (s_recibidas == NULL) return;

    uint32_t ahora = millis();

    // La dirección del otro módulo se aprende al recibir su primera trama, pero
    // darlo de alta como destino se hace aquí y no en la interrupción de la
    // radio. Si ya está dado de alta, no cuesta nada.
    if (s_pareja_conocida) asegurar_peer(s_pareja);

    // Se vacía la cola entera: son tramas pequeñas y llegan de a pocas.
    trama_t trama;
    while (xQueueReceive(s_recibidas, &trama, 0) == pdTRUE) atender_trama(&trama);

    repetir_pendiente(ahora);

#if ROL_ESCLAVO
    tareas_del_esclavo(ahora);
#else
    tareas_del_maestro(ahora);

    // La primera vez que aparece el esclavo hay que mandarle el horario sin
    // esperar a su TRAMA_ESTADO.
    if (s_pareja_conocida && s_version_enviando == 0 && horario_version() != 0 &&
        enlace_pareja_viva()) {
        empezar_envio_horario();
    }
#endif
}
