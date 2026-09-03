//
//  horario.c
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//

#include "horario.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cJSON.h"
#include "comun.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "red.h"
#include "reloj.h"
#include "timbre.h"

static const char *TAG = "horario";

// El maestro guarda el JSON tal cual llegó del servidor. El esclavo no ve ese
// JSON nunca: guarda la versión compacta que le manda el maestro por la radio.
#define RUTA_HORARIO RUTA_ALMACEN "/horario.json"
#define RUTA_HORARIO_BIN RUTA_ALMACEN "/horario.bin"
#define MAGIA_BIN 0x53575231u  // "SWR1", para no leer un archivo de otra cosa

typedef struct {
    timbre_programado_t items[MAX_TIMBRES];
    uint8_t cantidad;
} lista_timbres_t;

// ---- Estado protegido por s_candado ----
// Lo escribe la tarea de red al sincronizar y lo lee el bucle de control.
static SemaphoreHandle_t s_candado;

static lista_timbres_t s_habitual;

static bool s_hay_especial = false;
static char s_especial_nombre[33] = "";
static char s_especial_inicio[11] = "";  // "2026-08-03"
static char s_especial_fin[11] = "";
static lista_timbres_t s_especial;

// Estos dos los lee el detector de sismos. Son valores de 32 bits, se leen y
// escriben de una sola vez, así que no necesitan candado.
static float s_umbral_sismico_g = 0.4f;
static int s_sismo_duracion_min_ms = 800;

// Huella del horario cargado. El maestro la manda en cada latido y el esclavo
// la compara con la suya para saber si tiene que pedir el horario nuevo.
static uint32_t s_version = 0;

// El minuto ya atendido, para no timbrar dos veces a las 07:00:00 y 07:00:30.
// Solo lo toca el bucle de control.
static char s_minuto_procesado[6] = "";

static void tomar(void) { xSemaphoreTake(s_candado, portMAX_DELAY); }
static void soltar(void) { xSemaphoreGive(s_candado); }

// Un número de 32 bits que resume un texto (algoritmo FNV-1a). Dos horarios
// iguales dan el mismo número y dos distintos, casi con seguridad, no. Sirve
// para que el esclavo sepa de un vistazo si su horario es el de ahora sin
// tener que compararlo entero.
static uint32_t huella(const char *texto) {
    uint32_t h = 2166136261u;
    for (const uint8_t *p = (const uint8_t *)texto; *p != '\0'; p++) {
        h ^= *p;
        h *= 16777619u;
    }
    return h == 0 ? 1 : h;  // 0 queda reservado para "todavía no hay horario"
}

// ============================================================
// Leer el JSON del servidor
// ============================================================

static void texto_de(const cJSON *objeto, const char *clave, char *destino, size_t tam,
                     const char *por_defecto) {
    const cJSON *valor = cJSON_GetObjectItemCaseSensitive(objeto, clave);
    const char *s = (cJSON_IsString(valor) && valor->valuestring) ? valor->valuestring : por_defecto;
    strlcpy(destino, s, tam);
}

static double numero_de(const cJSON *objeto, const char *clave, double por_defecto) {
    const cJSON *valor = cJSON_GetObjectItemCaseSensitive(objeto, clave);
    return cJSON_IsNumber(valor) ? valor->valuedouble : por_defecto;
}

// Copia un arreglo de timbres del JSON a una lista.
static void copiar_timbres(const cJSON *arreglo, lista_timbres_t *destino) {
    static const char *NOMBRES_DIAS[6] = {"lunes", "martes", "miercoles",
                                          "jueves", "viernes", "sabado"};
    destino->cantidad = 0;
    if (!cJSON_IsArray(arreglo)) return;

    const cJSON *entrada = NULL;
    cJSON_ArrayForEach(entrada, arreglo) {
        if (destino->cantidad >= MAX_TIMBRES) break;
        timbre_programado_t *tp = &destino->items[destino->cantidad++];

        texto_de(entrada, "id", tp->id, sizeof(tp->id), "");
        texto_de(entrada, "etiqueta", tp->etiqueta, sizeof(tp->etiqueta), "");
        texto_de(entrada, "hora", tp->hora, sizeof(tp->hora), "00:00");
        tp->duracion_seg = (uint8_t)numero_de(entrada, "duracionSeg", 5);

        // "lunes".."sabado" → bits 0..5, en el mismo orden que reloj_dia_indice().
        tp->dias = 0;
        const cJSON *dias = cJSON_GetObjectItemCaseSensitive(entrada, "dias");
        const cJSON *dia = NULL;
        cJSON_ArrayForEach(dia, dias) {
            if (!cJSON_IsString(dia) || !dia->valuestring) continue;
            for (int i = 0; i < 6; i++) {
                if (strcmp(dia->valuestring, NOMBRES_DIAS[i]) == 0) tp->dias |= (1 << i);
            }
        }
    }
}

bool horario_aplicar_json(const char *json, bool recien_del_servidor) {
    cJSON *doc = cJSON_Parse(json);
    if (doc == NULL) {
        ESP_LOGW(TAG, "JSON inválido");
        return false;
    }

    s_umbral_sismico_g = (float)numero_de(doc, "umbralSismicoG", 0.4);
    s_sismo_duracion_min_ms = (int)numero_de(doc, "sismoDuracionMinMs", 800);
    s_version = huella(json);

    tomar();
    copiar_timbres(cJSON_GetObjectItemCaseSensitive(doc, "habitual"), &s_habitual);

    const cJSON *especial = cJSON_GetObjectItemCaseSensitive(doc, "especial");
    s_hay_especial = cJSON_IsObject(especial);
    if (s_hay_especial) {
        texto_de(especial, "nombre", s_especial_nombre, sizeof(s_especial_nombre), "");
        texto_de(especial, "fechaInicio", s_especial_inicio, sizeof(s_especial_inicio), "");
        texto_de(especial, "fechaFin", s_especial_fin, sizeof(s_especial_fin), "");
        copiar_timbres(cJSON_GetObjectItemCaseSensitive(especial, "timbres"), &s_especial);
    } else {
        s_especial.cantidad = 0;
    }
    uint8_t cantidad = s_habitual.cantidad;
    bool hay_especial = s_hay_especial;
    soltar();

    if (recien_del_servidor && !reloj_valida()) {
        char fecha[11], hora[6];
        texto_de(doc, "fechaServidor", fecha, sizeof(fecha), "");
        texto_de(doc, "horaServidor", hora, sizeof(hora), "");
        if (fecha[0] != '\0' && hora[0] != '\0') reloj_fijar_desde_servidor(fecha, hora);
    }

    cJSON_Delete(doc);

    // El mismo JSON del servidor se guarda tal cual: una sola forma del dato.
    if (recien_del_servidor) {
        FILE *f = fopen(RUTA_HORARIO, "w");
        if (f != NULL) {
            fputs(json, f);
            fclose(f);
        } else {
            ESP_LOGW(TAG, "no se pudo guardar el horario en la flash");
        }
    }

    ESP_LOGI(TAG, "%d timbres habituales%s", cantidad, hay_especial ? " + horario especial" : "");
    return true;
}

// ============================================================
// El horario apretado que viaja al esclavo por la radio
// ============================================================
//
// El esclavo no habla con el servidor, así que su horario se lo manda el
// maestro por ESP-NOW. Como por ahí solo caben 250 bytes por trama, no se
// manda el JSON sino un arreglo de `timbre_compacto_t` (24 bytes cada uno) más
// un resumen con los metadatos. El esclavo lo guarda en su flash y desde ahí
// timbra solo, aunque el maestro se apague.

uint32_t horario_version(void) { return s_version; }

void horario_resumen(horario_resumen_t *salida) {
    if (salida == NULL) return;
    memset(salida, 0, sizeof(*salida));

    tomar();
    salida->version = s_version;
    salida->cant_habitual = s_habitual.cantidad;
    salida->cant_especial = s_hay_especial ? s_especial.cantidad : 0;
    salida->hay_especial = s_hay_especial;
    strlcpy(salida->especial_nombre, s_especial_nombre, sizeof(salida->especial_nombre));
    strlcpy(salida->especial_inicio, s_especial_inicio, sizeof(salida->especial_inicio));
    strlcpy(salida->especial_fin, s_especial_fin, sizeof(salida->especial_fin));
    soltar();

    salida->umbral_sismico_g = s_umbral_sismico_g;
    salida->sismo_duracion_min_ms = (uint16_t)s_sismo_duracion_min_ms;
}

// Ojo: se llama con el candado ya tomado.
static void apretar(const timbre_programado_t *origen, timbre_compacto_t *destino) {
    int hh = 0, mm = 0;
    sscanf(origen->hora, "%d:%d", &hh, &mm);
    destino->hora = (uint8_t)hh;
    destino->minuto = (uint8_t)mm;
    destino->duracion_seg = origen->duracion_seg;
    destino->dias = origen->dias;
    strlcpy(destino->etiqueta, origen->etiqueta, sizeof(destino->etiqueta));
}

uint8_t horario_exportar(uint16_t desde, timbre_compacto_t *destino, uint8_t max) {
    uint8_t copiados = 0;

    tomar();
    // Los dos horarios se numeran seguidos: 0..cant_habitual-1 son los de
    // siempre y a partir de ahí van los del especial.
    uint16_t total_habitual = s_habitual.cantidad;
    uint16_t total = total_habitual + (s_hay_especial ? s_especial.cantidad : 0);

    for (uint16_t i = desde; i < total && copiados < max; i++) {
        const timbre_programado_t *tp = (i < total_habitual)
                                            ? &s_habitual.items[i]
                                            : &s_especial.items[i - total_habitual];
        apretar(tp, &destino[copiados++]);
    }
    soltar();

    return copiados;
}

// Lo contrario: de la trama de radio a la lista con la que se timbra.
static void desapretar(const timbre_compacto_t *origen, timbre_programado_t *destino) {
    destino->id[0] = '\0';  // el esclavo no reporta a la API: no necesita el UUID

    // La etiqueta llega de fuera y podría venir sin fin de cadena: se copia
    // acotada a lo que mide el campo y se termina a mano.
    char etiqueta[sizeof(origen->etiqueta) + 1];
    memcpy(etiqueta, origen->etiqueta, sizeof(origen->etiqueta));
    etiqueta[sizeof(origen->etiqueta)] = '\0';
    strlcpy(destino->etiqueta, etiqueta, sizeof(destino->etiqueta));

    snprintf(destino->hora, sizeof(destino->hora), "%02u:%02u", origen->hora % 24u,
             origen->minuto % 60u);
    destino->duracion_seg = origen->duracion_seg;
    destino->dias = origen->dias;
}

static void guardar_binario(const horario_resumen_t *resumen, const timbre_compacto_t *timbres,
                            uint16_t cantidad) {
    FILE *f = fopen(RUTA_HORARIO_BIN, "wb");
    if (f == NULL) {
        ESP_LOGW(TAG, "no se pudo guardar el horario en la flash");
        return;
    }
    uint32_t magia = MAGIA_BIN;
    fwrite(&magia, sizeof(magia), 1, f);
    fwrite(resumen, sizeof(*resumen), 1, f);
    fwrite(&cantidad, sizeof(cantidad), 1, f);
    if (cantidad > 0) fwrite(timbres, sizeof(timbres[0]), cantidad, f);
    fclose(f);
}

// `guardar` es false cuando el horario acaba de salir de la flash: no tiene
// sentido volver a escribir lo mismo en cada arranque.
static void aplicar_binario(const horario_resumen_t *resumen, const timbre_compacto_t *timbres,
                            uint16_t cantidad, bool guardar) {
    if (resumen == NULL || (timbres == NULL && cantidad > 0)) return;

    // Se cree lo que dice el resumen, pero sin pasarse de lo que llegó ni de lo
    // que cabe en las listas: una trama corrupta no puede escribir fuera.
    uint8_t habituales = resumen->cant_habitual;
    if (habituales > MAX_TIMBRES) habituales = MAX_TIMBRES;
    if (habituales > cantidad) habituales = (uint8_t)cantidad;

    uint8_t especiales = resumen->hay_especial ? resumen->cant_especial : 0;
    if (especiales > MAX_TIMBRES) especiales = MAX_TIMBRES;
    if (habituales + especiales > cantidad) especiales = (uint8_t)(cantidad - habituales);

    s_umbral_sismico_g = resumen->umbral_sismico_g;
    s_sismo_duracion_min_ms = resumen->sismo_duracion_min_ms;
    s_version = resumen->version;

    tomar();
    s_habitual.cantidad = habituales;
    for (uint8_t i = 0; i < habituales; i++) desapretar(&timbres[i], &s_habitual.items[i]);

    s_hay_especial = resumen->hay_especial;
    s_especial.cantidad = especiales;
    for (uint8_t i = 0; i < especiales; i++) {
        desapretar(&timbres[habituales + i], &s_especial.items[i]);
    }
    strlcpy(s_especial_nombre, resumen->especial_nombre, sizeof(s_especial_nombre));
    strlcpy(s_especial_inicio, resumen->especial_inicio, sizeof(s_especial_inicio));
    strlcpy(s_especial_fin, resumen->especial_fin, sizeof(s_especial_fin));
    soltar();

    if (guardar) guardar_binario(resumen, timbres, (uint16_t)(habituales + especiales));
    ESP_LOGI(TAG, "horario del maestro: %u timbres%s (versión %08lx)", habituales,
             s_hay_especial ? " + especial" : "", (unsigned long)s_version);
}

void horario_aplicar_binario(const horario_resumen_t *resumen, const timbre_compacto_t *timbres,
                             uint16_t cantidad) {
    aplicar_binario(resumen, timbres, cantidad, true);
}

// ============================================================
// Arranque: el horario sale de la flash (RF-28)
// ============================================================

// El horario que el esclavo guardó la última vez que habló con el maestro.
// Devuelve false si no hay nada guardado o el archivo no sirve.
static bool cargar_binario_de_flash(void) {
    FILE *f = fopen(RUTA_HORARIO_BIN, "rb");
    if (f == NULL) return false;

    uint32_t magia = 0;
    horario_resumen_t resumen;
    uint16_t cantidad = 0;
    bool ok = fread(&magia, sizeof(magia), 1, f) == 1 && magia == MAGIA_BIN &&
              fread(&resumen, sizeof(resumen), 1, f) == 1 &&
              fread(&cantidad, sizeof(cantidad), 1, f) == 1 && cantidad <= MAX_TIMBRES_TOTAL;

    timbre_compacto_t *timbres = NULL;
    if (ok && cantidad > 0) {
        timbres = calloc(cantidad, sizeof(timbre_compacto_t));
        ok = timbres != NULL && fread(timbres, sizeof(timbre_compacto_t), cantidad, f) == cantidad;
    }
    fclose(f);

    if (!ok) {
        ESP_LOGW(TAG, "el horario guardado no sirve; se pedirá otro al maestro");
        free(timbres);
        remove(RUTA_HORARIO_BIN);
        return false;
    }

    // Se aplica sin volver a escribirlo: acaba de salir de la flash.
    aplicar_binario(&resumen, timbres, cantidad, false);
    free(timbres);
    return true;
}

void horario_iniciar(void) {
    s_candado = xSemaphoreCreateMutex();

    FILE *f = fopen(RUTA_HORARIO, "r");
    if (f == NULL) {
        if (!cargar_binario_de_flash()) ESP_LOGI(TAG, "sin horario guardado todavía");
        return;
    }

    fseek(f, 0, SEEK_END);
    long tam = ftell(f);
    fseek(f, 0, SEEK_SET);

    char *json = (tam > 0) ? malloc(tam + 1) : NULL;
    if (json == NULL) {
        fclose(f);
        ESP_LOGW(TAG, "el horario guardado no cabe en memoria (%ld bytes)", tam);
        return;
    }

    size_t leidos = fread(json, 1, tam, f);
    json[leidos] = '\0';
    fclose(f);

    horario_aplicar_json(json, false);
    free(json);
}

// ============================================================
// Decidir qué suena y cuándo
// ============================================================

// Ojo: estas dos se llaman con el candado ya tomado.

// Comparación de textos "yyyy-MM-dd": ordena igual que las fechas.
static bool especial_vigente_sin_candado(const struct tm *t) {
    if (!s_hay_especial) return false;
    char hoy[11];
    strftime(hoy, sizeof(hoy), "%Y-%m-%d", t);
    return strcmp(s_especial_inicio, hoy) <= 0 && strcmp(hoy, s_especial_fin) <= 0;
}

static const lista_timbres_t *vigente_sin_candado(const struct tm *t) {
    return especial_vigente_sin_candado(t) ? &s_especial : &s_habitual;
}

void horario_revisar(void) {
    struct tm t;
    if (!reloj_hora_local(&t)) return;

    int dia = reloj_dia_indice(&t);
    if (dia < 0) return;

    char minuto[6];
    snprintf(minuto, sizeof(minuto), "%02d:%02d", t.tm_hour, t.tm_min);
    if (strcmp(minuto, s_minuto_procesado) == 0) return;
    strcpy(s_minuto_procesado, minuto);

    // Se copian los timbres que coinciden y se suelta el candado ANTES de
    // accionar el relé y escribir en la flash: así la tarea de red no se queda
    // esperando. Cuatro es de sobra; a la misma hora no hay más de uno.
    timbre_programado_t coinciden[4];
    int cuantos = 0;

    tomar();
    const lista_timbres_t *h = vigente_sin_candado(&t);
    for (int i = 0; i < h->cantidad && cuantos < 4; i++) {
        const timbre_programado_t *tp = &h->items[i];
        if ((tp->dias & (1 << dia)) == 0) continue;
        if (strcmp(tp->hora, minuto) != 0) continue;
        coinciden[cuantos++] = *tp;
    }
    soltar();

    for (int i = 0; i < cuantos; i++) {
        ESP_LOGI(TAG, "timbre automático: %s %s", coinciden[i].hora, coinciden[i].etiqueta);
        timbre_activar(coinciden[i].duracion_seg, coinciden[i].etiqueta);
        // RF-17: a la bitácora, con el id del timbre programado.
        red_encolar_activacion("automatico", coinciden[i].id, coinciden[i].duracion_seg);
    }
}

bool horario_proximo(const struct tm *t, timbre_programado_t *salida) {
    int dia = reloj_dia_indice(t);
    if (dia < 0) return false;

    char ahora[6];
    snprintf(ahora, sizeof(ahora), "%02d:%02d", t->tm_hour, t->tm_min);

    bool hallado = false;
    tomar();
    const lista_timbres_t *h = vigente_sin_candado(t);
    for (int i = 0; i < h->cantidad; i++) {
        const timbre_programado_t *tp = &h->items[i];
        if ((tp->dias & (1 << dia)) == 0) continue;
        if (strcmp(tp->hora, ahora) < 0) continue;  // ya pasó
        if (!hallado || strcmp(tp->hora, salida->hora) < 0) {
            *salida = *tp;
            hallado = true;
        }
    }
    soltar();
    return hallado;
}

bool horario_especial_vigente(const struct tm *t) {
    tomar();
    bool vigente = especial_vigente_sin_candado(t);
    soltar();
    return vigente;
}

void horario_especial_nombre(char *destino, size_t tam) {
    tomar();
    strlcpy(destino, s_especial_nombre, tam);
    soltar();
}

float horario_umbral_sismico(void) { return s_umbral_sismico_g; }

int horario_sismo_duracion_min_ms(void) { return s_sismo_duracion_min_ms; }
