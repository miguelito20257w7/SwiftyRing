# Firmware del módulo de timbre · SwiftyRing

Firmware del módulo físico ESP32-WROOM del Sistema de Timbre Escolar
(RF-15, RF-18..RF-31): acciona el timbre según el horario sincronizado,
responde al botón físico y a las órdenes de la app, detecta sismos con el
MPU-6050 y muestra el estado en una pantalla OLED SH1106. Opera de forma
autónoma sin internet; el horario vive en su memoria flash (LittleFS).

## Hardware

| Componente | Pin ESP32 | Nota |
|---|---|---|
| Relé de estado sólido (timbre) | GPIO 26 | Activo en ALTO |
| Botón de timbre manual | GPIO 27 | Contra GND, pull-up interno |
| OLED SH1106 1.3" (I2C) | SDA 21 · SCL 22 | Dirección estándar 0x3C |
| MPU-6050 (I2C) | SDA 21 · SCL 22 | Mismo bus, dirección 0x68 |

## Configurar

```bash
cp SwiftyRingTimbre/config.example.h SwiftyRingTimbre/config.h
```

Editar `config.h`: red WiFi, `API_BASE` (la IP del servidor Vapor, no
`localhost`) y `DEVICE_API_KEY` (la misma del `.env` del backend).

## Compilar y flashear (arduino-cli)

```bash
arduino-cli core install esp32:esp32 --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli lib install ArduinoJson U8g2
arduino-cli compile --fqbn esp32:esp32:esp32 SwiftyRingTimbre
arduino-cli upload --fqbn esp32:esp32:esp32 -p /dev/cu.usbserial-0001 SwiftyRingTimbre
```

(El puerto exacto aparece con `arduino-cli board list`.)

## Cómo habla con el backend

Todas las rutas llevan la cabecera `X-Device-Key`:

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
