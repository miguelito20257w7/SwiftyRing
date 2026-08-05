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

static const char *TAG = "reloj";

static bool s_valida = false;

void reloj_iniciar(void) {
    setenv("TZ", TZ_COLOMBIA, 1);
    tzset();

    // El cliente NTP queda encendido: cuando el WiFi conecte, se pondrá en
    // hora solo. No se espera aquí a que responda.
    esp_sntp_config_t cfg = ESP_NETIF_SNTP_DEFAULT_CONFIG(NTP_SERVIDOR);
    esp_err_t err = esp_netif_sntp_init(&cfg);
    if (err != ESP_OK) ESP_LOGW(TAG, "NTP no arrancó (%s)", esp_err_to_name(err));
}

bool reloj_hora_local(struct tm *t) {
    time_t ahora;
    time(&ahora);
    localtime_r(&ahora, t);
    s_valida = (t->tm_year + 1900) >= 2020;
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
}

int reloj_dia_indice(const struct tm *t) {
    if (t->tm_wday == 0) return -1;  // domingo
    return t->tm_wday - 1;
}
