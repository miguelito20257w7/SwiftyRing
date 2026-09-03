//
//  sismo.h
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  Detección de sismos mediante procesamiento espectral y STA/LTA recursivo:
//  - Filtro paso banda Butterworth de 4to orden (0.5 Hz - 10.0 Hz) en cascada Biquad.
//  - Cociente STA/LTA (Earle & Shearer) con congelamiento de fondo (LTA freeze).
//  - Validación cuadrática por tasa de Velocidad Absoluta Acumulada (CAV).
//  - Confirmación cruzada entre módulos vía radio ESP-NOW (RF-19).
//

#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

// Inicializa el puerto UART para el coprocesador ESP-01S.
esp_err_t sismo_iniciar(void);

// Atiende las tramas UART recibidas a 100 Hz.
void sismo_atender_uart(void);

// Máquina de confirmación entre módulos (o decisión autónoma) y disparo del timbre.
void sismo_atender(void);

// Aviso de sacudida recibido desde el otro módulo por ESP-NOW.
void sismo_sacudida_remota(float pico_g, uint32_t duracion_ms);

// Estado de enlace con el coprocesador serie
bool sismo_coprocesador_conectado(void);

// Telemetría para debug y visualización
float sismo_ax(void);
float sismo_ay(void);
float sismo_az(void);
float sismo_dynamic_magnitude(void);
float sismo_ratio_actual(void);
float sismo_sta_energy(void);
float sismo_lta_energy(void);
float sismo_cav_rate(void);
float sismo_pico_actual(void);
float sismo_temperatura(void);
int sismo_estado(void);
int sismo_contador_muestras(void);
int sismo_muestras_requeridas(void);
bool sismo_agitacion_activa(void);
