# Los archivos .c del firmware y los componentes de ESP-IDF que usan.
# Al añadir un archivo nuevo hay que apuntarlo aquí.

idf_component_register(
    SRCS
        "main.c"
        "reloj.c"
        "rtc.c"
        "horario.c"
        "timbre.c"
        "sismo.c"
        "red.c"
        "canal.c"
        "enlace.c"
        "pantalla.c"
        "sh1106.c"
        "led_rgb.c"
    INCLUDE_DIRS "."
    REQUIRES
        esp_driver_gpio # el relé y el botón
        esp_driver_i2c  # el bus de la pantalla y el RTC DS3231
        esp_driver_uart # receptor serie del coprocesador inercial ESP-01S
        esp_wifi        # WiFi y también ESP-NOW (esp_now.h vive aquí)
        esp_netif
        esp_event
        esp_http_client
        mbedtls         # verificar el certificado del servidor (esp_crt_bundle)
        nvs_flash       # el WiFi guarda ahí su configuración
        spiffs          # horario y cola de reportes en la flash
        esp_timer       # millis()
        esp_hw_support  # esp_random(), para el número de sesión del enlace
        led_strip       # LED RGB direccionable WS2812 en ESP32-S3
)

# ---- Maestro o esclavo ----
#
# El mismo código sirve para los dos módulos. Con -DESCLAVO=1 se compila el del
# otro edificio: sin WiFi, sin API y sin botón (ver config.h y enlace.c).
#
#   idf.py -B build build flash monitor                      → maestro
#   idf.py -B build-esclavo -DESCLAVO=1 build flash monitor  → esclavo
#
# Cada rol en su propia carpeta de compilación: si se usa la misma, cada cambio
# de rol obliga a recompilar el proyecto entero.
if(ESCLAVO)
    target_compile_definitions(${COMPONENT_LIB} PRIVATE ROL_ESCLAVO=1)
    message(STATUS "SwiftyRing: compilando el módulo ESCLAVO (ESP-NOW, sin WiFi ni API)")
else()
    message(STATUS "SwiftyRing: compilando el módulo MAESTRO")
endif()

# cJSON ya no viene dentro de ESP-IDF desde la versión 6.0: se declara como
# dependencia en idf_component.yml y el propio idf.py la descarga.
