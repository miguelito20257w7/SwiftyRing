//
//  nodo-sensor-esp01.ino
//  SwiftyRing · Coprocesador inercial (ESP-01S + MPU-6050)
//
//  Nodo sensor sellado: muestrea el MPU-6050 por I2C a ~100 Hz y transmite
//  la trama binaria de 18 bytes por UART a 115200 baudios hacia el ESP32 principal.
//  Nota: El sensor opera en rango ±2g (16384 LSB/g, valor por defecto de hardware).
//

#include <Wire.h>
#include <ESP8266WiFi.h>

#define MPU_ADDR 0x68
#define PIN_SDA 0
#define PIN_SCL 2

uint8_t buffer[14];

void setup() {
  // UART a alta velocidad para minimizar latencia en la línea
  WiFi.mode(WIFI_OFF);
  WiFi.forceSleepBegin();
  delay(1);
  Serial.begin(115200);

  // Inicializar I2C por software en GPIO0 y GPIO2
  Wire.begin(PIN_SDA, PIN_SCL);
  Wire.setClock(400000); // 400 kHz

  // Despertar el MPU-6050 (por defecto arranca en modo Sleep)
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x6B); // Registro PWR_MGMT_1
  Wire.write(0x00); // Escribir 0 para encender oscilador interno
  Wire.endTransmission(true);
}

void loop() {
  // Solicitar lectura continua a partir del registro 0x3B (ACCEL_XOUT_H)
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x3B);
  Wire.endTransmission(false); // Restart
  Wire.requestFrom(MPU_ADDR, 14, true);

  if (Wire.available() == 14) {
    uint8_t checksum = 0;

    // Cabecera de sincronización
    Serial.write(0xAA);
    Serial.write(0x55);

    // Transmitir los 14 bytes y calcular checksum
    for (int i = 0; i < 14; i++) {
      buffer[i] = Wire.read();
      checksum ^= buffer[i];
      Serial.write(buffer[i]);
    }

    // Pie de paquete: Checksum y delimitador
    Serial.write(checksum);
    Serial.write(0x0D);
  }

  // Tasa de muestreo de ~100 Hz (ajustable según tu aplicación)
  delay(10);
}
