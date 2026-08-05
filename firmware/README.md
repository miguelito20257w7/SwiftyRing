# Firmware del módulo de timbre · SwiftyRing

Firmware del módulo físico ESP32-WROOM del Sistema de Timbre Escolar
(RF-15, RF-18..RF-31): acciona el timbre según el horario sincronizado,
responde al botón físico y a las órdenes de la app, detecta sismos con el
MPU-6050 y muestra el estado en una pantalla OLED SH1106. Opera de forma
autónoma sin internet; el horario vive en su memoria flash.

## Dos versiones del mismo firmware

| Carpeta | Framework | Se compila con |
|---|---|---|
| **`timbre-idf/`** | **ESP-IDF** (la actual) | `idf.py` |
| `SwiftyRingTimbre/` | Arduino | `arduino-cli` |

Hacen exactamente lo mismo y hablan igual con el backend. La de ESP-IDF es el
porteo de la de Arduino: mismo comportamiento, escrito con las librerías
nativas de Espressif en vez de con las de Arduino.

## Hardware

La versión de ESP-IDF sirve para dos placas, y **cada una lleva los cables en
pines distintos**:

| Componente | ESP32-WROOM | ESP32-S3 | Nota |
|---|---|---|---|
| Relé de estado sólido (timbre) | GPIO 26 | GPIO 4 | Activo en ALTO |
| Botón de timbre manual | GPIO 27 | GPIO 5 | Contra GND, pull-up interno |
| OLED SH1106 1.3" (I2C) | SDA 21 · SCL 22 | SDA 8 · SCL 9 | Dirección estándar 0x3C |
| MPU-6050 (I2C) | SDA 21 · SCL 22 | SDA 8 · SCL 9 | Mismo bus, dirección 0x68 |
| LED RGB (WS2812) en placa | N/A | GPIO 48 | Alerta visual estroboscópica al sonar el timbre |

No se pueden usar los mismos: en el ESP32-S3 los GPIO 26 y 27 están cableados
a la memoria flash interna del módulo, y el GPIO 22 ni siquiera existe (la
numeración salta del 21 al 26). El firmware elige los pines solo, según el
chip para el que se compile; no hay que editar nada.

La versión de Arduino es solo para el ESP32-WROOM.

---

# Versión ESP-IDF (`timbre-idf/`)

## 1. Activar ESP-IDF

Ya está instalado (**v6.0.2**, puesta con el instalador de Espressif). En cada
terminal nueva hay que activarla antes de compilar: eso es lo que hace que
exista el comando `idf.py`.

```bash
. ~/.espressif/tools/activate_idf_v6.0.2.sh
```

> Ojo: el `export.sh` de dentro de `esp-idf/` **no** funciona en esta
> instalación (busca un entorno de Python que no existe). El de arriba es el
> bueno.

Probado con la v6.0.2. Hace falta la **5.2 como mínimo**, porque el firmware
usa el driver I2C nuevo (`i2c_master`), que no existe en las anteriores.

## 2. Configurar

```bash
cp firmware/timbre-idf/main/config.example.h firmware/timbre-idf/main/config.h
```

Editar `config.h`: red WiFi, `API_BASE` (la IP del servidor Vapor, no
`localhost`) y `DEVICE_API_KEY` (la misma del `.env` del backend). No se sube a
git.

## 3. Elegir la placa

Una sola vez por placa. Este comando deja el proyecto preparado para ese chip
(escoge sus pines y su tamaño de flash) y **borra el `sdkconfig`**, que se
vuelve a generar solo:

```bash
cd firmware/timbre-idf && idf.py set-target esp32s3
```

Para el WROOM es `idf.py set-target esp32`. Si no te acuerdas de para cuál
está preparado ahora mismo, mira la primera línea que imprime `idf.py build`.

## 4. Compilar, flashear y ver los mensajes

```bash
cd firmware/timbre-idf && idf.py build
```

```bash
cd firmware/timbre-idf && idf.py -p /dev/cu.usbserial-0001 flash monitor
```

El puerto exacto sale con `ls /dev/cu.*`. Para salir del monitor: `Ctrl-]`.

La primera vez conviene borrar la flash entera, porque cambia la tabla de
particiones respecto al firmware de Arduino:

```bash
cd firmware/timbre-idf && idf.py -p /dev/cu.usbserial-0001 erase-flash
```

## Cómo está organizado

Cada archivo es una de las secciones que en Arduino estaban numeradas dentro
del `.ino`:

| Archivo | Qué hace |
|---|---|
| `main.c` | Arranque y bucle de control (relé, botón, sismo, horario, pantalla) |
| `red.c` | WiFi, consultas HTTP al backend y cola de reportes |
| `horario.c` | El horario en memoria y en flash; decide qué timbre suena |
| `timbre.c` | El relé y el botón físico |
| `sismo.c` | El acelerómetro MPU-6050 y el detector de sismos |
| `pantalla.c` | Lo que se dibuja en el OLED |
| `sh1106.c` + `fuente5x7.h` | Driver de la pantalla y las letras, píxel a píxel |
| `reloj.c` | Hora por NTP y hora del servidor |

La única librería externa es **cJSON**, que se declara en
`main/idf_component.yml` y la descarga `idf.py` sola la primera vez. (Venía
dentro de ESP-IDF hasta la 5.x; en la 6.0 la sacaron del núcleo.)

El firmware corre en **dos tareas** de FreeRTOS: el bucle de control (que nunca
se bloquea) y la tarea de red (que sí puede quedarse esperando al servidor).
Esa separación es la ventaja principal del porteo: en la versión de Arduino,
una consulta HTTP lenta congelaba también la pantalla y el botón.

## Qué cambió respecto a la versión de Arduino

Mismo comportamiento, distintas herramientas:

| Arduino | ESP-IDF |
|---|---|
| `WiFi.h` | `esp_wifi` + `esp_netif` |
| `HTTPClient` | `esp_http_client` |
| `ArduinoJson` | `cJSON` |
| `LittleFS` | SPIFFS (partición `almacen`, ver `partitions.csv`) |
| `U8g2lib` | `sh1106.c`, escrito para este proyecto |
| `loop()` con `millis()` | Dos tareas de FreeRTOS |

---

# Versión Arduino (`SwiftyRingTimbre/`)

Se conserva porque es la que ya está probada en la placa.

```bash
cp SwiftyRingTimbre/config.example.h SwiftyRingTimbre/config.h
```

```bash
arduino-cli core install esp32:esp32 --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
```

```bash
arduino-cli lib install ArduinoJson U8g2
```

```bash
arduino-cli compile --fqbn esp32:esp32:esp32 SwiftyRingTimbre
```

```bash
arduino-cli upload --fqbn esp32:esp32:esp32 -p /dev/cu.usbserial-0001 SwiftyRingTimbre
```

---

## Cómo habla con el backend

Igual en las dos versiones. Todas las rutas llevan la cabecera `X-Device-Key`:

| Ruta | Cada cuánto | Para qué |
|---|---|---|
| `GET /api/dispositivo/horario` | 5 min y al arrancar | Horario completo + calibración sísmica → flash (RF-28) |
| `GET /api/dispositivo/comandos` | 2 s | Órdenes de timbre de la app (RNF-04) + latido "en línea" |
| `POST /api/dispositivo/activaciones` | al sonar | Bitácora de timbres automáticos y del botón (RF-17) |
| `POST /api/dispositivo/sismos` | al detectar | Evento sísmico confirmado (RF-22, RF-23) |

Sin conexión, los reportes esperan en una cola en flash y se envían al
reconectar (RF-30). El detector de sismos exige vibración **sostenida**
(duración y fracción de muestras activas), no un pico suelto: así un camión
o un portazo no evacúan el colegio (RF-19).
