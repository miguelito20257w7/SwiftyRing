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
//   · Recibe datos inerciales del coprocesador ESP-01S por UART y, ante un
//     patrón de sismo sostenido, activa la alarma y reporta el evento
//     (RF-18, RF-19, RF-22).
//   · Obtiene la hora inmediatamente de su RTC físico DS3231 al encender y
//     la mantiene calibrada por NTP / Vapor.
//   · Muestra en la pantalla OLED la hora, el próximo timbre y el tiempo
//     restante; indica cuando el timbre está sonando y cuando está en modo
//     offline (RF-24 a RF-27).
//   · Todo lo que suena queda reportado al servidor para la bitácora
//     (RF-17); si no hay conexión, el reporte espera en una cola en flash y
//     se envía al reconectar (RF-30).
//
//  El firmware corre en DOS tareas de FreeRTOS:
//
//   · el bucle de control (esta función): relé, botón, sismo UART, horario y
//     pantalla. Da una vuelta cada 5-10 ms y nunca se bloquea.
//   · la tarea de red (red.c): WiFi y consultas HTTP, que pueden tardar
//     segundos. Va aparte justo por eso: que el servidor no conteste no puede
//     retrasar un timbre.
//
//  ---- Los dos módulos ----
//
//  El mismo código sirve para los dos módulos del sistema; lo que cambia es el
//  interruptor ROL_ESCLAVO, que se pone al compilar:
//
//    idf.py -B build build flash                    → el MAESTRO
//    idf.py -B build-esclavo -DESCLAVO=1 build flash → el ESCLAVO
//

#include <stdio.h>

#include "comun.h"
#include "config.h"
#include "driver/i2c_master.h"
#include "enlace.h"
#include "esp_log.h"
#include "esp_spiffs.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "horario.h"
#include "led_rgb.h"
#include "nvs_flash.h"
#include "pantalla.h"
#include "red.h"
#include "reloj.h"
#include "sismo.h"
#include "timbre.h"

static const char *TAG = "swiftyring";

#define INTERVALO_PANTALLA_MS 250

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

static i2c_master_bus_handle_t iniciar_bus_i2c(i2c_port_num_t puerto, int sda, int scl) {
    i2c_master_bus_config_t cfg = {
        .i2c_port = puerto,
        .sda_io_num = sda,
        .scl_io_num = scl,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    i2c_master_bus_handle_t bus = NULL;
    ESP_ERROR_CHECK(i2c_new_master_bus(&cfg, &bus));
    return bus;
}

void app_main(void) {
    ESP_LOGI(TAG, "SwiftyRing · módulo de timbre (%s)", ROL_ESCLAVO ? "esclavo" : "maestro");

    iniciar_nvs();
    iniciar_flash();

    // Bus I2C 0 (I2C_NUM_0): dedicado a la pantalla OLED SH1106
    i2c_master_bus_handle_t bus_pantalla = iniciar_bus_i2c(I2C_OLED_PORT, PIN_I2C_OLED_SDA, PIN_I2C_OLED_SCL);
    pantalla_iniciar(bus_pantalla);
    pantalla_mensaje("SwiftyRing", ROL_ESCLAVO ? "Modulo 2..." : "Iniciando...");

    // Bus I2C 1 (I2C_NUM_1): dedicado al RTC físico DS3231 (aislado de la pantalla)
    i2c_master_bus_handle_t bus_rtc = iniciar_bus_i2c(I2C_RTC_PORT, PIN_I2C_RTC_SDA, PIN_I2C_RTC_SCL);
    reloj_iniciar(bus_rtc);

    timbre_iniciar();
    led_rgb_iniciar();
    sismo_iniciar();  // Receptor UART para el coprocesador ESP-01S

    // El horario guardado se carga de flash: si el módulo amaneció sin internet,
    // el timbre del primer bloque suena igual (RF-31).
    horario_iniciar();

#if ROL_ESCLAVO
    // Sin WiFi ni servidor: la radio la enciende enlace.c solo para ESP-NOW, y
    // la hora llega en el latido del maestro (o desde el RTC local si lo tiene).
    enlace_iniciar();
#else
    red_iniciar();
    enlace_iniciar();  // ESP-NOW va montado sobre el WiFi que ya dejó red_iniciar

    xTaskCreate(red_tarea, "red", 6144, NULL, 5, NULL);
#endif

    // ---- Bucle de control ----
    uint32_t t_pantalla = 0;

    while (true) {
        uint32_t ahora = millis();

        timbre_atender();
        led_rgb_atender(timbre_activo());
        horario_revisar();
        enlace_atender();      // lo que llegó del otro módulo, y los latidos
        sismo_atender_uart();  // drena y procesa las tramas del ESP-01S sin latencia
        sismo_atender();       // evaluación de sacudida propia y confirmación remota

        if (ahora - t_pantalla >= INTERVALO_PANTALLA_MS) {
            t_pantalla = ahora;
            pantalla_dibujar();
        }

        vTaskDelay(pdMS_TO_TICKS(5));
    }
}
