#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "driver/i2c_master.h"

#define I2C_PORT_NUM            I2C_NUM_0
#define I2C_SCL_IO              1
#define I2C_SDA_IO              2
#define I2C_FREQ_HZ             100000

static const char *TAG = "I2C_SCANNER";

void app_main(void)
{
    ESP_LOGI(TAG, "Iniciando escáner I2C...");

    // 1. Configuración del bus maestro
    i2c_master_bus_config_t bus_config = {
        .i2c_port = I2C_PORT_NUM,
        .sda_io_num = I2C_SDA_IO,
        .scl_io_num = I2C_SCL_IO,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };

    i2c_master_bus_handle_t bus_handle;
    ESP_ERROR_CHECK(i2c_new_master_bus(&bus_config, &bus_handle));

    printf("\n     0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f\n");
    printf("00:         ");

    int devices_found = 0;

    // El rango estándar de 7 bits es de 0x03 a 0x77
    for (uint8_t addr = 3; addr < 0x78; addr++) {
        if (addr % 16 == 0) {
            printf("\n%02x:", addr);
        }

        // i2c_master_probe envía un byte con la dirección y verifica el bit ACK
        esp_err_t ret = i2c_master_probe(bus_handle, addr, 50);

        if (ret == ESP_OK) {
            printf(" %02x", addr);
            devices_found++;
        } else {
            printf(" --");
        }
    }

    printf("\n\nEscaneo finalizado. Dispositivos detectados: %d\n", devices_found);

    // Liberar recursos del bus si no se vuelve a usar de inmediato
    ESP_ERROR_CHECK(i2c_del_master_bus(bus_handle));
}
