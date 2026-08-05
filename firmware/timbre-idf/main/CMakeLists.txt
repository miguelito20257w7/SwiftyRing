# Los archivos .c del firmware y los componentes de ESP-IDF que usan.
# Al añadir un archivo nuevo hay que apuntarlo aquí.

idf_component_register(
    SRCS
        "main.c"
        "reloj.c"
        "horario.c"
        "timbre.c"
        "sismo.c"
        "red.c"
        "pantalla.c"
        "sh1106.c"
    INCLUDE_DIRS "."
    REQUIRES
        esp_driver_gpio # el relé y el botón
        esp_driver_i2c  # el bus de la pantalla y el acelerómetro
        esp_wifi
        esp_netif
        esp_event
        esp_http_client
        nvs_flash       # el WiFi guarda ahí su configuración
        spiffs          # horario y cola de reportes en la flash
        esp_timer       # millis()
)

# cJSON ya no viene dentro de ESP-IDF desde la versión 6.0: se declara como
# dependencia en idf_component.yml y el propio idf.py la descarga.

