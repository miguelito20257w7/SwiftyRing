//
//  rtc.c
//  SwiftyRing · Firmware del módulo de timbre (ESP-IDF)
//
//  Driver I2C para el RTC de alta precisión DS3231.
//

#include "rtc.h"

#include <string.h>
#include <sys/time.h>

#include "comun.h"
#include "esp_log.h"

static const char *TAG = "rtc";

#define DS3231_DIRECCION       0x68
#define DS3231_REG_TIEMPO      0x00
#define DS3231_REG_ESTADO      0x0F
#define DS3231_FLAG_OSF        (1 << 7)  // Oscillator Stop Flag en reg 0x0F

static i2c_master_dev_handle_t s_rtc = NULL;
static bool s_presente = false;

// Conversiones BCD <-> Binario
static inline uint8_t bcd_a_dec(uint8_t val) {
    return (uint8_t)(((val >> 4) * 10) + (val & 0x0F));
}

static inline uint8_t dec_a_bcd(uint8_t val) {
    return (uint8_t)(((val / 10) << 4) | (val % 10));
}

esp_err_t rtc_iniciar(i2c_master_bus_handle_t bus) {
    i2c_device_config_t cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = DS3231_DIRECCION,
        .scl_speed_hz = 400000,
    };
    esp_err_t err = i2c_master_bus_add_device(bus, &cfg, &s_rtc);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "no se pudo registrar el dispositivo I2C del DS3231 (%s)", esp_err_to_name(err));
        return err;
    }

    // Probar si contesta leyendo el registro de estado (0x0F)
    uint8_t reg = DS3231_REG_ESTADO;
    uint8_t estado = 0;
    err = i2c_master_transmit_receive(s_rtc, &reg, 1, &estado, 1, 100);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "el RTC DS3231 no contesta en el bus I2C (0x68)");
        s_presente = false;
        return err;
    }

    s_presente = true;
    bool osf = (estado & DS3231_FLAG_OSF) != 0;
    if (osf) {
        ESP_LOGW(TAG, "DS3231 detectado pero el oscilador estuvo parado (batería descargada o nuevo)");
    } else {
        ESP_LOGI(TAG, "DS3231 listo y oscilador en marcha");
    }

    return ESP_OK;
}

bool rtc_presente(void) {
    return s_presente;
}

static bool leer_datos_rtc(struct tm *t, bool *osf_activo) {
    if (!s_presente || s_rtc == NULL) return false;

    // 1. Leer registros de tiempo 0x00..0x06
    uint8_t reg = DS3231_REG_TIEMPO;
    uint8_t d[7] = {0};
    if (i2c_master_transmit_receive(s_rtc, &reg, 1, d, sizeof(d), 100) != ESP_OK) {
        return false;
    }

    // 2. Leer registro de estado 0x0F para ver bandera OSF
    reg = DS3231_REG_ESTADO;
    uint8_t estado = 0;
    if (i2c_master_transmit_receive(s_rtc, &reg, 1, &estado, 1, 100) == ESP_OK) {
        if (osf_activo) *osf_activo = (estado & DS3231_FLAG_OSF) != 0;
    }

    memset(t, 0, sizeof(*t));
    t->tm_sec = bcd_a_dec(d[0] & 0x7F);
    t->tm_min = bcd_a_dec(d[1] & 0x7F);
    t->tm_hour = bcd_a_dec(d[2] & 0x3F);  // Formato 24h
    t->tm_wday = (d[3] & 0x07) - 1;      // 1..7 -> 0..6 (domingo es 0)
    if (t->tm_wday < 0 || t->tm_wday > 6) t->tm_wday = 0;
    t->tm_mday = bcd_a_dec(d[4] & 0x3F);
    t->tm_mon = bcd_a_dec(d[5] & 0x1F) - 1;  // 1..12 -> 0..11
    t->tm_year = bcd_a_dec(d[6]) + 100;      // 00..99 -> años desde 1900 (2000 -> 100)
    t->tm_isdst = 0;

    return true;
}

bool rtc_hora_valida(void) {
    struct tm t;
    bool osf = true;
    if (!leer_datos_rtc(&t, &osf)) return false;
    if (osf) return false;
    int anio_completo = t.tm_year + 1900;
    return (anio_completo >= 2026 && anio_completo <= 2099);
}

bool rtc_leer_y_fijar_sistema(void) {
    struct tm t;
    bool osf = false;
    if (!leer_datos_rtc(&t, &osf)) return false;

    int anio_completo = t.tm_year + 1900;
    if (osf || anio_completo < 2026) {
        ESP_LOGW(TAG, "hora del RTC no válida o desconfigurada (%04d-%02d-%02d %02d:%02d:%02d, OSF=%d)",
                 anio_completo, t.tm_mon + 1, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec, osf);
        return false;
    }

    time_t epoca = mktime(&t);
    if (epoca <= 0) return false;

    struct timeval tv = {.tv_sec = epoca, .tv_usec = 0};
    settimeofday(&tv, NULL);

    ESP_LOGI(TAG, "hora aplicada desde el RTC físico: %04d-%02d-%02d %02d:%02d:%02d",
             anio_completo, t.tm_mon + 1, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec);
    return true;
}

bool rtc_actualizar_desde_sistema(void) {
    if (!s_presente || s_rtc == NULL) return false;

    time_t ahora;
    time(&ahora);
    struct tm t;
    localtime_r(&ahora, &t);

    int anio_completo = t.tm_year + 1900;
    if (anio_completo < 2026) return false;  // No escribir una hora inválida en el RTC

    uint8_t buffer[8];
    buffer[0] = DS3231_REG_TIEMPO;
    buffer[1] = dec_a_bcd((uint8_t)t.tm_sec);
    buffer[2] = dec_a_bcd((uint8_t)t.tm_min);
    buffer[3] = dec_a_bcd((uint8_t)t.tm_hour); // 24h
    buffer[4] = (uint8_t)(t.tm_wday + 1);      // 1..7
    buffer[5] = dec_a_bcd((uint8_t)t.tm_mday);
    buffer[6] = dec_a_bcd((uint8_t)(t.tm_mon + 1));
    buffer[7] = dec_a_bcd((uint8_t)(anio_completo % 100));

    if (i2c_master_transmit(s_rtc, buffer, sizeof(buffer), 100) != ESP_OK) {
        ESP_LOGW(TAG, "falló la escritura de hora en el DS3231");
        return false;
    }

    // Limpiar bandera OSF en registro 0x0F
    uint8_t reg_estado = DS3231_REG_ESTADO;
    uint8_t estado = 0;
    if (i2c_master_transmit_receive(s_rtc, &reg_estado, 1, &estado, 1, 100) == ESP_OK) {
        if (estado & DS3231_FLAG_OSF) {
            uint8_t limpiar[2] = {DS3231_REG_ESTADO, (uint8_t)(estado & ~DS3231_FLAG_OSF)};
            i2c_master_transmit(s_rtc, limpiar, sizeof(limpiar), 100);
        }
    }

    ESP_LOGI(TAG, "RTC DS3231 calibrado con la hora del sistema: %04d-%02d-%02d %02d:%02d:%02d",
             anio_completo, t.tm_mon + 1, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec);
    return true;
}

static float s_ultima_temp_leida = -100.0f;
static uint32_t s_ultimo_muestreo_temp = 0;

float rtc_temperatura(void) {
    if (!s_presente || s_rtc == NULL) return -100.0f;
    uint32_t ahora = millis();
    if (s_ultima_temp_leida > -50.0f && (ahora - s_ultimo_muestreo_temp) < 10000) {
        return s_ultima_temp_leida;
    }
    uint8_t reg = 0x11;
    uint8_t d[2] = {0};
    if (i2c_master_transmit_receive(s_rtc, &reg, 1, d, 2, 50) != ESP_OK) {
        return s_ultima_temp_leida;
    }
    int8_t msb = (int8_t)d[0];
    float lsb = (float)(d[1] >> 6) * 0.25f;
    s_ultima_temp_leida = (float)msb + lsb;
    s_ultimo_muestreo_temp = ahora;
    return s_ultima_temp_leida;
}
