//
//  reloj.c
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//

#include "reloj.h"

#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>

#include "config.h"
#include "esp_log.h"
#include "esp_netif_sntp.h"
#include "rtc.h"

static const char *TAG = "reloj";

static bool s_valida = false;

#if !ROL_ESCLAVO
static void sntp_sync_cb(struct timeval *tv) {
    (void)tv;
    ESP_LOGI(TAG, "sincronización SNTP exitosa; actualizando RTC DS3231");
    s_valida = true;
    rtc_actualizar_desde_sistema();
}
#endif

void reloj_iniciar(i2c_master_bus_handle_t bus) {
    setenv("TZ", TZ_COLOMBIA, 1);
    tzset();

    // 1. Inicializar RTC DS3231 en el bus I2C si se proporcionó bus
    if (bus != NULL) {
        rtc_iniciar(bus);
        if (rtc_leer_y_fijar_sistema()) {
            s_valida = true;
            ESP_LOGI(TAG, "hora inicial fijada desde el RTC físico DS3231");
        } else {
            ESP_LOGW(TAG, "RTC DS3231 sin hora válida o ausente; esperando sincronización de red");
        }
    }

#if ROL_ESCLAVO
    // El esclavo no está en ninguna red: no hay NTP. Su hora llega en
    // el latido del maestro por reloj_fijar_epoca() o desde su propio RTC si lo tuviera.
    ESP_LOGI(TAG, "sin NTP: la hora la pone el maestro por el enlace");
#else
    // El cliente NTP queda encendido: cuando el WiFi conecte, se pondrá en
    // hora solo y actualizará el RTC físico mediante el callback.
    esp_sntp_config_t cfg = ESP_NETIF_SNTP_DEFAULT_CONFIG(NTP_SERVIDOR);
    cfg.sync_cb = sntp_sync_cb;
    esp_err_t err = esp_netif_sntp_init(&cfg);
    if (err != ESP_OK) ESP_LOGW(TAG, "NTP no arrancó (%s)", esp_err_to_name(err));
#endif
}

bool reloj_hora_local(struct tm *t) {
    time_t ahora;
    time(&ahora);
    localtime_r(&ahora, t);
    s_valida = (t->tm_year + 1900) >= 2026;
    return s_valida;
}

bool reloj_valida(void) { return s_valida; }

void reloj_fijar_desde_servidor(const char *fecha, const char *hora) {
    if (fecha == NULL || hora == NULL) return;

    int anio, mes, dia, hh, mm;
    if (sscanf(fecha, "%d-%d-%d", &anio, &mes, &dia) != 3) return;
    if (sscanf(hora, "%d:%d", &hh, &mm) != 2) return;

    struct tm t = {0};
    t.tm_year = anio - 1900;
    t.tm_mon = mes - 1;
    t.tm_mday = dia;
    t.tm_hour = hh;
    t.tm_min = mm;
    t.tm_isdst = 0;

    // mktime interpreta la fecha en la zona horaria ya configurada.
    time_t epoca = mktime(&t);
    if (epoca <= 0) return;

    struct timeval tv = {.tv_sec = epoca, .tv_usec = 0};
    settimeofday(&tv, NULL);
    s_valida = true;
    ESP_LOGI(TAG, "hora puesta desde el servidor: %s %s", fecha, hora);

    // Mantener sincronizado el RTC físico
    rtc_actualizar_desde_sistema();
}

void reloj_fijar_epoca(time_t epoca, uint32_t tolerancia_seg) {
    // Una hora anterior a 2026 es que el otro módulo tampoco la tiene todavía.
    if (epoca < 1767225600) return;  // 2026-01-01

    time_t ahora;
    time(&ahora);
    double desvio = difftime(epoca, ahora);
    if (desvio < 0) desvio = -desvio;

    if (s_valida && desvio <= (double)tolerancia_seg) return;

    struct timeval tv = {.tv_sec = epoca, .tv_usec = 0};
    settimeofday(&tv, NULL);
    s_valida = true;
    ESP_LOGI(TAG, "hora puesta desde el enlace (desvío de %.0f s)", desvio);

    // Si el esclavo tiene RTC, también lo mantiene actualizado
    rtc_actualizar_desde_sistema();
}

int reloj_dia_indice(const struct tm *t) {
    if (t->tm_wday == 0) return -1;  // domingo
    return t->tm_wday - 1;
}
