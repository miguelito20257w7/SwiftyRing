//
//  sismo.c
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//

#include "sismo.h"

#include <math.h>
#include <stdbool.h>

#include "comun.h"
#include "esp_log.h"
#include "horario.h"
#include "red.h"
#include "timbre.h"

static const char *TAG = "sismo";

#define MPU_DIRECCION 0x68
#define MPU_REG_DESPERTAR 0x6B
#define MPU_REG_RANGO 0x1C
#define MPU_REG_ACELERACION 0x3B

// En rango ±8g el sensor entrega 4096 unidades por cada g.
#define UNIDADES_POR_G 4096.0f

static i2c_master_dev_handle_t s_mpu = NULL;
static bool s_presente = false;

esp_err_t sismo_iniciar(i2c_master_bus_handle_t bus) {
    i2c_device_config_t cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = MPU_DIRECCION,
        .scl_speed_hz = 400000,
    };
    esp_err_t err = i2c_master_bus_add_device(bus, &cfg, &s_mpu);
    if (err != ESP_OK) return err;

    // El MPU-6050 arranca dormido: hay que escribirle un 0 para despertarlo.
    uint8_t despertar[2] = {MPU_REG_DESPERTAR, 0x00};
    err = i2c_master_transmit(s_mpu, despertar, sizeof(despertar), 100);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "el MPU-6050 no responde; sin detección de sismos");
        return err;
    }

    uint8_t rango[2] = {MPU_REG_RANGO, 0x10};  // ±8g
    i2c_master_transmit(s_mpu, rango, sizeof(rango), 100);

    s_presente = true;
    ESP_LOGI(TAG, "MPU-6050 listo");
    return ESP_OK;
}

// Magnitud de la aceleración en g, o -1 si el sensor no contesta.
static float leer_aceleracion_g(void) {
    if (!s_presente) return -1;

    uint8_t registro = MPU_REG_ACELERACION;
    uint8_t datos[6];
    if (i2c_master_transmit_receive(s_mpu, &registro, 1, datos, sizeof(datos), 100) != ESP_OK) {
        return -1;
    }

    int16_t ax = (int16_t)((datos[0] << 8) | datos[1]);
    int16_t ay = (int16_t)((datos[2] << 8) | datos[3]);
    int16_t az = (int16_t)((datos[4] << 8) | datos[5]);

    float x = ax / UNIDADES_POR_G;
    float y = ay / UNIDADES_POR_G;
    float z = az / UNIDADES_POR_G;
    return sqrtf(x * x + y * y + z * z);
}

// Cómo se distingue un sismo de un camión (RF-19), en palabras simples:
//
//  · Un golpe o un camión pasando sacude fuerte pero POCO TIEMPO: picos
//    sueltos de menos de medio segundo.
//  · Un sismo sacude de forma SOSTENIDA: la vibración supera el umbral una y
//    otra vez durante más de `sismoDuracionMinMs` milisegundos.
//
//  Por eso el detector no mira un pico, mira la HISTORIA: cuándo empezó la
//  agitación, cuánto lleva, y qué fracción de las muestras del episodio
//  estuvo agitada. Solo si dura lo suficiente Y fue agitación continua
//  (>40% de muestras activas) se declara sismo.
static uint32_t s_inicio = 0;  // cuándo empezó el episodio (0 = no hay episodio)
static uint32_t s_ultima_actividad = 0;
static int s_muestras_total = 0;
static int s_muestras_activas = 0;
static float s_pico_g = 0;
static uint32_t s_ultimo_evento = 0;  // guarda de 60 s entre eventos

void sismo_muestrear(void) {
    float magnitud = leer_aceleracion_g();
    if (magnitud < 0) return;

    // En reposo la magnitud es 1g (la gravedad); lo que importa es el exceso.
    float exceso = fabsf(magnitud - 1.0f);
    bool agitada = exceso > horario_umbral_sismico();
    uint32_t ahora = millis();

    if (s_inicio == 0) {
        if (!agitada) return;
        // Arranca un episodio de vibración.
        s_inicio = ahora;
        s_ultima_actividad = ahora;
        s_muestras_total = 0;
        s_muestras_activas = 0;
        s_pico_g = 0;
    }

    s_muestras_total++;
    if (agitada) {
        s_ultima_actividad = ahora;
        s_muestras_activas++;
        if (exceso > s_pico_g) s_pico_g = exceso;
    }

    // 300 ms sin actividad = el episodio terminó; toca evaluarlo.
    if (ahora - s_ultima_actividad < 300) return;

    uint32_t duracion_ms = s_ultima_actividad - s_inicio;
    float fraccion_activa =
        s_muestras_total > 0 ? (float)s_muestras_activas / s_muestras_total : 0;
    bool es_sismo = duracion_ms >= (uint32_t)horario_sismo_duracion_min_ms() &&
                    fraccion_activa > 0.4f && (ahora - s_ultimo_evento) > 60000;

    if (es_sismo) {
        s_ultimo_evento = ahora;
        ESP_LOGW(TAG, "sismo: %.2f g durante %lu ms", s_pico_g, (unsigned long)duracion_ms);
        // RF-22: la alarma suena YA, sin preguntarle a nadie. 30 s de evacuación.
        timbre_activar(30, "SISMO");
        red_encolar_sismo(s_pico_g, duracion_ms);
    }

    s_inicio = 0;  // listo para el próximo episodio
}
