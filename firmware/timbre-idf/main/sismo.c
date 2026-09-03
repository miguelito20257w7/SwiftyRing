//
//  sismo.c
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  Sistema de Detección de Movimientos Fuertes Mediante MPU-6050:
//  1. Filtro Paso Banda Butterworth de 4to orden (0.5 Hz a 10.0 Hz) vía Direct Form II Transposed.
//  2. Algoritmo STA/LTA recursivo (Earle & Shearer) con congelamiento de fondo (LTA Freeze).
//  3. Validación por Tasa de Velocidad Absoluta Acumulada (CAV) y persistencia temporal.
//  4. Confirmación cruzada entre módulos vía ESP-NOW (RF-19) y disparo de relé (RF-22).
//

#include "sismo.h"

#include <math.h>
#include <stdbool.h>

#include "comun.h"
#include "config.h"
#include "driver/uart.h"
#include "enlace.h"
#include "esp_log.h"
#include "horario.h"
#include "red.h"
#include "timbre.h"

static const char *TAG = "sismo";

// En el ESP-01S el MPU-6050 opera en escala ±2g (16384 LSB/g)
#define UNIDADES_POR_G   16384.0f
#define UART_BUFFER_RX   512

#define FS 100.0f
#define DT (1.0f / FS)

// Constantes STA/LTA (Earle & Shearer / Trnkoczy)
#define T_STA 0.8f
#define T_LTA 20.0f
#define C_STA (1.0f / (T_STA * FS))   // 0.0125f (N_sta = 80 muestras)
#define C_LTA (1.0f / (T_LTA * FS))   // 0.0005f (N_lta = 2000 muestras)

// Umbrales de decisión normalizados
#define THRESHOLD_TRIGGER    4.5f   // Alfa: Disparo relativo
#define THRESHOLD_DETRIGGER  1.5f   // Beta: Apagado / descarte
#define MIN_PGA_PISO_G       0.015f // 15 mg: Piso de ruido físico irreducible del MPU-6050
#define MIN_CAV_RATE         0.020f // Tasa mínima de Velocidad Absoluta Acumulada (g*s/s)

// ============================================================
// Filtro Digital IIR Butterworth en cascada Biquad
// ============================================================

typedef struct {
    float b0, b1, b2;
    float a1, a2;
    float w1, w2;
} biquad_section_t;

static inline void biquad_configure(biquad_section_t *s, float b0, float b1, float b2, float a1, float a2) {
    s->b0 = b0; s->b1 = b1; s->b2 = b2;
    s->a1 = a1; s->a2 = a2;
    s->w1 = 0.0f; s->w2 = 0.0f;
}

static inline float biquad_update(biquad_section_t *s, float in) {
    float out = s->b0 * in + s->w1;
    s->w1 = s->b1 * in - s->a1 * out + s->w2;
    s->w2 = s->b2 * in - s->a2 * out;
    return out;
}

typedef struct {
    biquad_section_t stage[2];
} butterworth_bandpass_t;

static void butterworth_init(butterworth_bandpass_t *f) {
    // Etapa 0: Pasa bajo Butterworth de 10.0 Hz
    biquad_configure(&f->stage[0], 0.06186950f, 0.12373900f, 0.06186950f, -1.19543300f, 0.45055520f);
    // Etapa 1: Pasa alto Butterworth de 0.5 Hz (supresión total de gravedad DC y derivas)
    biquad_configure(&f->stage[1], 1.00000000f, -2.00000000f, 1.00000000f, -1.95592900f, 0.95698630f);
}

static inline float butterworth_update(butterworth_bandpass_t *f, float in) {
    return biquad_update(&f->stage[1], biquad_update(&f->stage[0], in));
}

static butterworth_bandpass_t s_filter_x;
static butterworth_bandpass_t s_filter_y;
static butterworth_bandpass_t s_filter_z;
static bool s_filtros_iniciados = false;

// ============================================================
// Parser de tramas binarias UART del ESP-01S (18 bytes)
// ============================================================

typedef enum {
    BUSCAR_AA = 0,
    BUSCAR_55,
    LEER_DATOS,
    LEER_CHECKSUM,
    LEER_FIN
} estado_parser_t;

static estado_parser_t s_estado = BUSCAR_AA;
static uint8_t s_payload[14];
static uint8_t s_indice_payload = 0;
static uint8_t s_xor_calc = 0;
static uint8_t s_xor_rx = 0;
static uint32_t s_ultimo_paquete_uart = 0;

// Telemetría en tiempo real
static float s_ax = 0.0f;
static float s_ay = 0.0f;
static float s_az = 1.0f;
static float s_temp_mpu = 0.0f;

// Variables de energía y decisión sísmica
typedef enum {
    STATE_QUIET = 0,
    STATE_PRE_TRIGGER = 1,
    STATE_CONFIRMED_SEISM = 2
} detection_state_t;

static detection_state_t s_system_state = STATE_QUIET;
static int s_state_counter = 0;
static float s_cumulative_velocity = 0.0f;
static float s_computed_cav_rate = 0.0f;
static float s_dynamic_magnitude = 0.0f;
static float s_current_ratio = 1.0f;
static float s_sta_energy = 0.0f;
static float s_lta_energy = 1.0e-4f;
static float s_pico_sismo = 0.0f;

static void anotar_sacudida_propia(float pico_g, uint32_t duracion_ms);

esp_err_t sismo_iniciar(void) {
    uart_config_t cfg = {
        .baud_rate = UART_SISMO_BAUD,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };

    esp_err_t err = uart_param_config(UART_SISMO_PORT, &cfg);
    if (err != ESP_OK) return err;

    err = uart_set_pin(UART_SISMO_PORT, PIN_UART_SISMO_TX, PIN_UART_SISMO_RX,
                       UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
    if (err != ESP_OK) return err;

    err = uart_driver_install(UART_SISMO_PORT, UART_BUFFER_RX, 0, 0, NULL, 0);
    if (err != ESP_OK) return err;

    ESP_LOGI(TAG, "Receptor UART para ESP-01S listo en RX GPIO %d a %d baudios",
             PIN_UART_SISMO_RX, UART_SISMO_BAUD);
    return ESP_OK;
}

bool sismo_coprocesador_conectado(void) {
    return (s_ultimo_paquete_uart > 0 && (millis() - s_ultimo_paquete_uart) < 1000);
}

// Procesa una muestra de aceleración aplicando Butterworth Biquad + STA/LTA recursivo + CAV
static void procesar_muestra(float ax_raw, float ay_raw, float az_raw) {
    if (!s_filtros_iniciados) {
        butterworth_init(&s_filter_x);
        butterworth_init(&s_filter_y);
        butterworth_init(&s_filter_z);
        s_filtros_iniciados = true;
    }

    // 1. Filtrado Paso Banda Butterworth (0.5 Hz - 10.0 Hz)
    float ax_flt = butterworth_update(&s_filter_x, ax_raw);
    float ay_flt = butterworth_update(&s_filter_y, ay_raw);
    float az_flt = butterworth_update(&s_filter_z, az_raw);

    // 2. Magnitud dinámica y energía cuadrática instantánea (CF)
    float dynamic_magnitude = sqrtf(ax_flt * ax_flt + ay_flt * ay_flt + az_flt * az_flt);
    float instantaneous_energy = dynamic_magnitude * dynamic_magnitude;

    // 3. Integración recursiva STA (T = 0.8 s)
    s_sta_energy = C_STA * instantaneous_energy + (1.0f - C_STA) * s_sta_energy;

    // 4. Integración LTA con protección de congelamiento (LTA Freeze)
    // En reposo (STATE_QUIET) el LTA sigue las variaciones lentas del ruido ambiente (T = 20 s).
    // Durante una fase sísmica o pre-disparo, el LTA se congela para evitar que las ondas S
    // inflen el denominador y corten la alarma prematuramente.
    if (s_system_state == STATE_QUIET) {
        s_lta_energy = C_LTA * instantaneous_energy + (1.0f - C_LTA) * s_lta_energy;
        if (s_lta_energy < 1.0e-6f) s_lta_energy = 1.0e-6f;
    }

    s_current_ratio = s_sta_energy / (s_lta_energy + 1.0e-7f);
    s_dynamic_magnitude = dynamic_magnitude;
    s_ax = ax_raw;
    s_ay = ay_raw;
    s_az = az_raw;

    // WARMUP (5 segundos): Evita falso positivo al encender mientras los filtros se estabilizan
    static int s_warmup_samples = 0;
    if (s_warmup_samples < 500) {
        s_warmup_samples++;
        return; // Retorna antes de evaluar la máquina de estados
    }

    // Umbral de aceleración pico (PGA) mínima de control:
    // Exige superar el piso de ruido instrumental (15 mg) o el umbral configurado en la app
    float min_pga = fmaxf(MIN_PGA_PISO_G, horario_umbral_sismico());

    // Muestras mínimas requeridas a 100 Hz según sismoDuracionMinMs
    int min_sustained = (horario_sismo_duracion_min_ms() * 100) / 1000;
    if (min_sustained < 30) min_sustained = 30; // Mínimo 300 ms

    // 5. Máquina de estados determinista de confirmación sísmica
    switch (s_system_state) {
        case STATE_QUIET:
            if (s_current_ratio >= THRESHOLD_TRIGGER && dynamic_magnitude >= min_pga) {
                s_system_state = STATE_PRE_TRIGGER;
                s_state_counter = 1;
                s_cumulative_velocity = dynamic_magnitude * DT;
                s_pico_sismo = dynamic_magnitude;
            }
            break;

        case STATE_PRE_TRIGGER:
            s_cumulative_velocity += dynamic_magnitude * DT;
            if (dynamic_magnitude > s_pico_sismo) s_pico_sismo = dynamic_magnitude;

            if (s_current_ratio >= THRESHOLD_DETRIGGER) {
                s_state_counter++;
                s_computed_cav_rate = s_cumulative_velocity / (s_state_counter * DT);

                if (s_state_counter >= min_sustained) {
                    // Criterio normativo CAV: la aceleración debe aportar energía continua
                    if (s_computed_cav_rate >= MIN_CAV_RATE) {
                        s_system_state = STATE_CONFIRMED_SEISM;
                        ESP_LOGW(TAG, "¡SISMO CONFIRMADO POR STA/LTA! Pico: %.4f g, Ratio: %.1f, CAV: %.4f g*s/s",
                                 s_pico_sismo, s_current_ratio, s_computed_cav_rate);
                        anotar_sacudida_propia(s_pico_sismo, (s_state_counter * 1000) / 100);
                        enlace_avisar_sacudida(s_pico_sismo, (s_state_counter * 1000) / 100);
                    } else {
                        ESP_LOGI(TAG, "Perturbación rechazada por CAV insuficiente (%.4f < %.4f)",
                                 s_computed_cav_rate, MIN_CAV_RATE);
                        s_system_state = STATE_QUIET;
                        s_state_counter = 0;
                        s_cumulative_velocity = 0.0f;
                    }
                }
            } else {
                // Cayó por debajo de beta antes de la duración mínima: choque/portazo transitorio
                s_system_state = STATE_QUIET;
                s_state_counter = 0;
                s_cumulative_velocity = 0.0f;
            }
            break;

        case STATE_CONFIRMED_SEISM:
            s_cumulative_velocity += dynamic_magnitude * DT;
            if (dynamic_magnitude > s_pico_sismo) s_pico_sismo = dynamic_magnitude;

            if (s_current_ratio < THRESHOLD_DETRIGGER) {
                s_state_counter--;
                if (s_state_counter <= 0) {
                    s_system_state = STATE_QUIET;
                    s_state_counter = 0;
                    s_cumulative_velocity = 0.0f;
                    ESP_LOGI(TAG, "Sismo concluido. Reanudando rastreo ambiental basal LTA.");
                }
            } else {
                s_state_counter = min_sustained;
            }
            break;
    }

    // Telemetría periódica para calibración con la impresora 3D (10 Hz)
    static int s_calib_counter = 0;
    if (++s_calib_counter >= 10) {
        s_calib_counter = 0;
        ESP_LOGI(TAG, "CALIB | Mag Dinámica: %.4f g | STA/LTA Ratio: %.1f | Estado: %d | Umbral: %.3f g", 
                 dynamic_magnitude, s_current_ratio, (int)s_system_state, min_pga);
    }
}

// Lee el buffer UART y ejecuta el parser de la trama de 18 bytes
void sismo_atender_uart(void) {
    uint8_t byte = 0;
    while (uart_read_bytes(UART_SISMO_PORT, &byte, 1, 0) > 0) {
        switch (s_estado) {
            case BUSCAR_AA:
                if (byte == 0xAA) {
                    s_estado = BUSCAR_55;
                }
                break;

            case BUSCAR_55:
                if (byte == 0x55) {
                    s_estado = LEER_DATOS;
                    s_indice_payload = 0;
                    s_xor_calc = 0;
                } else if (byte == 0xAA) {
                    s_estado = BUSCAR_55;
                } else {
                    s_estado = BUSCAR_AA;
                }
                break;

            case LEER_DATOS:
                s_payload[s_indice_payload++] = byte;
                s_xor_calc ^= byte;
                if (s_indice_payload >= 14) {
                    s_estado = LEER_CHECKSUM;
                }
                break;

            case LEER_CHECKSUM:
                s_xor_rx = byte;
                s_estado = LEER_FIN;
                break;

            case LEER_FIN:
                if (byte == 0x0D && s_xor_calc == s_xor_rx) {
                    s_ultimo_paquete_uart = millis();

                    // Trama 100% íntegra. Decodificar ax, ay, az (Big-Endian de 16 bits)
                    int16_t raw_ax = (int16_t)((s_payload[0] << 8) | s_payload[1]);
                    int16_t raw_ay = (int16_t)((s_payload[2] << 8) | s_payload[3]);
                    int16_t raw_az = (int16_t)((s_payload[4] << 8) | s_payload[5]);
                    int16_t raw_temp = (int16_t)((s_payload[6] << 8) | s_payload[7]);

                    float ax = (float)raw_ax / UNIDADES_POR_G;
                    float ay = (float)raw_ay / UNIDADES_POR_G;
                    float az = (float)raw_az / UNIDADES_POR_G;

                    s_temp_mpu = (raw_temp / 340.0f) + 36.53f;

                    procesar_muestra(ax, ay, az);
                } else if (byte == 0xAA) {
                    s_estado = BUSCAR_55;
                    break;
                }
                s_estado = BUSCAR_AA;
                break;
        }
    }
}

// Getters de telemetría y diagnóstico
float sismo_ax(void) { return s_ax; }
float sismo_ay(void) { return s_ay; }
float sismo_az(void) { return s_az; }
float sismo_dynamic_magnitude(void) { return s_dynamic_magnitude; }
float sismo_ratio_actual(void) { return s_current_ratio; }
float sismo_sta_energy(void) { return s_sta_energy; }
float sismo_lta_energy(void) { return s_lta_energy; }
float sismo_cav_rate(void) { return s_computed_cav_rate; }
float sismo_pico_actual(void) { return s_pico_sismo; }
float sismo_temperatura(void) { return s_temp_mpu; }
int sismo_estado(void) { return (int)s_system_state; }
int sismo_contador_muestras(void) { return s_state_counter; }
int sismo_muestras_requeridas(void) {
    int m = (horario_sismo_duracion_min_ms() * 100) / 1000;
    return m < 30 ? 30 : m;
}
bool sismo_agitacion_activa(void) { return s_system_state != STATE_QUIET; }

// ============================================================
// Confirmación cruzada entre los dos módulos (RF-19)
// ============================================================

#define VENTANA_CONFIRMACION_MS 3000
#define GUARDA_ENTRE_EVENTOS_MS 60000

static bool s_propia_valida = false;
static uint32_t s_propia_t = 0;
static float s_propia_g = 0;
static uint32_t s_propia_ms = 0;

static bool s_remota_valida = false;
static uint32_t s_remota_t = 0;
static float s_remota_g = 0;

static uint32_t s_ultimo_evento = 0;  // Guarda de 60 s entre alarmas

static void anotar_sacudida_propia(float pico_g, uint32_t duracion_ms) {
    s_propia_valida = true;
    s_propia_t = millis();
    s_propia_g = pico_g;
    s_propia_ms = duracion_ms;
}

void sismo_sacudida_remota(float pico_g, uint32_t duracion_ms) {
    s_remota_valida = true;
    s_remota_t = millis();
    s_remota_g = pico_g;
    ESP_LOGW(TAG, "El otro módulo sintió %.2f g durante %lu ms", pico_g,
             (unsigned long)duracion_ms);
}

static uint32_t separacion(uint32_t a, uint32_t b) {
    uint32_t diff1 = a - b;
    uint32_t diff2 = b - a;
    return diff1 < diff2 ? diff1 : diff2;
}

void sismo_atender(void) {
    uint32_t ahora = millis();

    // El aviso del otro caduca tras la ventana
    if (s_remota_valida && ahora - s_remota_t > VENTANA_CONFIRMACION_MS) {
        s_remota_valida = false;
    }

    if (!s_propia_valida) return;

    bool solo = !enlace_pareja_viva();
    bool confirmada = s_remota_valida && separacion(s_propia_t, s_remota_t) <= VENTANA_CONFIRMACION_MS;

    // Aún en ventana de espera
    if (!solo && !confirmada && ahora - s_propia_t < VENTANA_CONFIRMACION_MS) return;

    if (solo || confirmada) {
        bool primera = (s_ultimo_evento == 0);
        if (primera || ahora - s_ultimo_evento > GUARDA_ENTRE_EVENTOS_MS) {
            s_ultimo_evento = ahora;
            ESP_LOGW(TAG, "SISMO %s: %.2f g durante %lu ms",
                     confirmada ? "confirmado por ambos módulos" : "(decisión autónoma)",
                     s_propia_g, (unsigned long)s_propia_ms);
            // RF-22: Alarma inmediata de 30 segundos
            timbre_activar(30, "SISMO");
            red_encolar_sismo(s_propia_g, s_propia_ms, confirmada, confirmada ? s_remota_g : 0);
        }
    } else {
        ESP_LOGI(TAG, "Sacudida de %.2f g descartada: el otro módulo no la sintió", s_propia_g);
    }

    s_propia_valida = false;
    s_remota_valida = false;
}
