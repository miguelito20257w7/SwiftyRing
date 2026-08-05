//
//  main.c
//  SwiftyRing · Módulo físico de timbre (ESP32-WROOM, ESP-IDF)
//
//  Qué hace este módulo, en una frase por requerimiento:
//
//   · Guarda el horario en su memoria flash y timbra solo, aunque no haya
//     internet (RF-28, RF-31).
//   · Acciona el relé del timbre cuando llega la hora programada, cuando se
//     pulsa el botón físico (RF-15, RF-16) o cuando la app lo ordena — la
//     orden se consulta al servidor cada 2 segundos (RNF-04).
//   · Vigila el acelerómetro MPU-6050 y, ante un patrón de sismo (no un
//     camión), activa la alarma por su cuenta y reporta el evento
//     (RF-18, RF-19, RF-22).
//   · Muestra en la pantalla OLED la hora, el próximo timbre y el tiempo
//     restante; indica cuando el timbre está sonando y cuando está en modo
//     offline (RF-24 a RF-27).
//   · Todo lo que suena queda reportado al servidor para la bitácora
//     (RF-17); si no hay conexión, el reporte espera en una cola en flash y
//     se envía al reconectar (RF-30).
//
//  El firmware corre en DOS tareas de FreeRTOS:
//
//   · el bucle de control (esta función): relé, botón, sismo, horario y
//     pantalla. Da una vuelta cada 10 ms y nunca se bloquea.
//   · la tarea de red (red.c): WiFi y consultas HTTP, que pueden tardar
//     segundos. Va aparte justo por eso: que el servidor no conteste no puede
//     retrasar un timbre.
//
//  Las dos tareas se pasan el trabajo con avisos, no con memoria compartida a
//  la brava: la red deja una orden y el bucle de control es el único que toca
//  el relé.
//

#include <stdio.h>

#include "comun.h"
#include "config.h"
#include "driver/i2c_master.h"
#include "esp_log.h"
#include "esp_spiffs.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "horario.h"
#include "nvs_flash.h"
#include "pantalla.h"
#include "red.h"
#include "reloj.h"
#include "sismo.h"
#include "timbre.h"

static const char *TAG = "swiftyring";

#define INTERVALO_PANTALLA_MS 250
#define INTERVALO_SISMO_MS 20  // 50 muestras por segundo

// El WiFi guarda su configuración en la partición NVS: hay que prepararla
// antes de arrancarlo.
static void iniciar_nvs(void) {
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);
}

// La partición de datos donde viven el horario y la cola de reportes. La
// primera vez que arranca el módulo está vacía y se formatea sola.
static void iniciar_flash(void) {
    esp_vfs_spiffs_conf_t cfg = {
        .base_path = RUTA_ALMACEN,
        .partition_label = "almacen",
        .max_files = 4,
        .format_if_mount_failed = true,
    };
    esp_err_t err = esp_vfs_spiffs_register(&cfg);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "la flash de datos no montó (%s)", esp_err_to_name(err));
        return;
    }

    size_t total = 0, usado = 0;
    if (esp_spiffs_info("almacen", &total, &usado) == ESP_OK) {
        ESP_LOGI(TAG, "flash de datos: %u KB usados de %u KB", (unsigned)(usado / 1024),
                 (unsigned)(total / 1024));
    }
}

static i2c_master_bus_handle_t iniciar_i2c(void) {
    i2c_master_bus_config_t cfg = {
        .i2c_port = I2C_NUM_0,
        .sda_io_num = PIN_I2C_SDA,
        .scl_io_num = PIN_I2C_SCL,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    i2c_master_bus_handle_t bus = NULL;
    ESP_ERROR_CHECK(i2c_new_master_bus(&cfg, &bus));
    return bus;
}

void app_main(void) {
    ESP_LOGI(TAG, "SwiftyRing · módulo de timbre");

    iniciar_nvs();
    iniciar_flash();

    i2c_master_bus_handle_t bus = iniciar_i2c();  // lo comparten pantalla y MPU-6050
    pantalla_iniciar(bus);
    pantalla_mensaje("SwiftyRing", "Iniciando...");

    timbre_iniciar();
    sismo_iniciar(bus);

    // El horario guardado se carga ANTES de tocar la red: si el colegio
    // amaneció sin internet, el timbre del primer bloque suena igual (RF-31).
    horario_iniciar();

    red_iniciar();
    reloj_iniciar();  // después de la red: el NTP necesita la pila de red lista

    xTaskCreate(red_tarea, "red", 6144, NULL, 5, NULL);

    // ---- Bucle de control ----
    uint32_t t_pantalla = 0;
    uint32_t t_sismo = 0;

    while (true) {
        uint32_t ahora = millis();

        timbre_atender();
        horario_revisar();

        if (ahora - t_sismo >= INTERVALO_SISMO_MS) {
            t_sismo = ahora;
            sismo_muestrear();
        }

        if (ahora - t_pantalla >= INTERVALO_PANTALLA_MS) {
            t_pantalla = ahora;
            pantalla_dibujar();
        }

        vTaskDelay(pdMS_TO_TICKS(10));
    }
}
