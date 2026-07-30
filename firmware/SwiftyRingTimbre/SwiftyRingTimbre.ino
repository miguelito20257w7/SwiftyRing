//
//  SwiftyRingTimbre.ino
//  SwiftyRing · Módulo físico de timbre (ESP32-WROOM)
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
//  El código está organizado en secciones numeradas; el `loop()` solo decide
//  cada cuánto corre cada una. No hay `delay()` largos: el timbre no puede
//  perder un minuto porque la pantalla estaba dibujando.
//

#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <LittleFS.h>
#include <Wire.h>
#include <U8g2lib.h>
#include <time.h>
#include "config.h"

// ============================================================
// 1. Estado global
// ============================================================

// Un timbre programado, tal como llega de /api/dispositivo/horario.
struct TimbreProgramado {
  char id[37];        // UUID, para reportar qué timbre sonó
  char etiqueta[33];  // "Inicio de clases"
  char hora[6];       // "07:00" (siempre con cero a la izquierda)
  uint8_t duracionSeg;
  uint8_t dias;       // Máscara de bits: bit 0 = lunes … bit 5 = sábado
};

const int MAX_TIMBRES = 32;

struct Horario {
  TimbreProgramado items[MAX_TIMBRES];
  uint8_t cantidad = 0;
};

Horario habitual;

// Horario especial (RF-10..12): si hoy cae dentro de su rango, manda él.
bool hayEspecial = false;
char especialNombre[33] = "";
char especialInicio[11] = "";  // "2026-08-03"
char especialFin[11] = "";
Horario especial;

// Calibración sísmica que baja del servidor (RF-19).
float umbralSismicoG = 1.2f;
int sismoDuracionMinMs = 800;

// Estado del timbre (relé).
bool timbreActivo = false;
unsigned long timbreHasta = 0;      // millis() en que se apaga
char timbreMotivo[33] = "";         // qué se muestra en pantalla

// Reloj: true cuando la hora es confiable (NTP o la hora del servidor).
bool horaValida = false;

// Conectividad.
bool enLinea = false;

// El minuto ya atendido, para no timbrar dos veces a las 07:00:00 y 07:00:30.
char minutoProcesado[6] = "";

// Pantalla: SH1106 1.3" 128x64 por I2C (RF-24).
U8G2_SH1106_128X64_NONAME_F_HW_I2C pantalla(U8G2_R0);

// Temporizadores del loop (todo por millis, nada bloqueante).
unsigned long tUltimoComando = 0;
unsigned long tUltimaSync = 0;
unsigned long tUltimaPantalla = 0;
unsigned long tUltimaMuestraSismo = 0;
unsigned long tUltimoIntentoWifi = 0;
unsigned long tUltimoFlushCola = 0;

const unsigned long INTERVALO_COMANDOS_MS = 2000;    // RNF-04: < 2 s
const unsigned long INTERVALO_SYNC_MS = 5UL * 60UL * 1000UL;
const unsigned long INTERVALO_PANTALLA_MS = 250;
const unsigned long INTERVALO_SISMO_MS = 20;         // 50 muestras/segundo
const unsigned long INTERVALO_WIFI_MS = 10000;
const unsigned long INTERVALO_FLUSH_COLA_MS = 15000;

// ============================================================
// 2. Arranque
// ============================================================

void setup() {
  Serial.begin(115200);
  Serial.println("\nSwiftyRing · módulo de timbre");

  pinMode(PIN_RELE, OUTPUT);
  digitalWrite(PIN_RELE, LOW);
  pinMode(PIN_BOTON, INPUT_PULLUP);

  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
  pantalla.begin();
  pantallaMensaje("SwiftyRing", "Iniciando...");

  if (!LittleFS.begin(true)) {  // true: formatea la flash la primera vez
    Serial.println("[FS] LittleFS no arranca");
  }

  iniciarMPU();

  // El horario guardado se carga ANTES de intentar la red: si el colegio
  // amaneció sin internet, el timbre del primer bloque suena igual (RF-31).
  cargarHorarioDeFlash();

  // Zona horaria de Colombia + NTP. Si el NTP no responde, la hora llegará
  // con la primera sincronización del servidor.
  configTzTime(TZ_COLOMBIA, NTP_SERVIDOR);

  conectarWifi();
  sincronizarHorario();
}

// ============================================================
// 3. El loop: un reloj de tareas
// ============================================================

void loop() {
  unsigned long ahora = millis();

  // Apagar el relé cuando se cumple la duración del toque.
  if (timbreActivo && ahora >= timbreHasta) {
    digitalWrite(PIN_RELE, LOW);
    timbreActivo = false;
  }

  atenderBoton();

  if (ahora - tUltimaMuestraSismo >= INTERVALO_SISMO_MS) {
    tUltimaMuestraSismo = ahora;
    muestrearSismo();
  }

  revisarHorario();

  if (ahora - tUltimaPantalla >= INTERVALO_PANTALLA_MS) {
    tUltimaPantalla = ahora;
    dibujarPantalla();
  }

  // ---- Tareas de red ----
  enLinea = (WiFi.status() == WL_CONNECTED);

  if (!enLinea && ahora - tUltimoIntentoWifi >= INTERVALO_WIFI_MS) {
    tUltimoIntentoWifi = ahora;
    conectarWifi();
  }

  if (enLinea) {
    if (ahora - tUltimoComando >= INTERVALO_COMANDOS_MS) {
      tUltimoComando = ahora;
      consultarComandos();
    }
    if (ahora - tUltimaSync >= INTERVALO_SYNC_MS) {
      sincronizarHorario();
    }
    if (ahora - tUltimoFlushCola >= INTERVALO_FLUSH_COLA_MS) {
      tUltimoFlushCola = ahora;
      enviarReportesPendientes();
    }
  }
}

// ============================================================
// 4. Reloj
// ============================================================

// Día de la semana como índice de la máscara: 0 = lunes … 5 = sábado.
// Devuelve -1 el domingo (el sistema no programa timbres ese día).
int diaIndice(const tm &t) {
  if (t.tm_wday == 0) return -1;   // domingo
  return t.tm_wday - 1;
}

bool leerHoraLocal(tm &t) {
  if (!getLocalTime(&t, 10)) return false;
  // Antes de sincronizar, el ESP32 cree estar en 1970: esa hora no sirve
  // para timbrar.
  horaValida = (t.tm_year + 1900) >= 2020;
  return horaValida;
}

// Fija el reloj con la fecha/hora que mandó el servidor, por si el NTP está
// bloqueado en la red del colegio.
void fijarHoraDelServidor(const char *fecha, const char *hora) {
  tm t = {};
  int anio, mes, dia, hh, mm;
  if (sscanf(fecha, "%d-%d-%d", &anio, &mes, &dia) != 3) return;
  if (sscanf(hora, "%d:%d", &hh, &mm) != 2) return;
  t.tm_year = anio - 1900;
  t.tm_mon = mes - 1;
  t.tm_mday = dia;
  t.tm_hour = hh;
  t.tm_min = mm;
  t.tm_isdst = 0;
  time_t epoch = mktime(&t);  // mktime interpreta en la TZ ya configurada
  if (epoch <= 0) return;
  timeval tv = { .tv_sec = epoch, .tv_usec = 0 };
  settimeofday(&tv, nullptr);
  horaValida = true;
}

// ============================================================
// 5. Horario: decidir qué suena y cuándo
// ============================================================

// ¿Rige hoy el horario especial? Comparación de textos "yyyy-MM-dd": ordena
// igual que las fechas.
bool especialVigente(const tm &t) {
  if (!hayEspecial) return false;
  char hoy[11];
  strftime(hoy, sizeof(hoy), "%Y-%m-%d", &t);
  return strcmp(especialInicio, hoy) <= 0 && strcmp(hoy, especialFin) <= 0;
}

Horario &horarioVigente(const tm &t) {
  return especialVigente(t) ? especial : habitual;
}

// Cada segundo: si entramos a un minuto nuevo, buscar timbres que coincidan
// con este día y esta hora (RF-07, RF-31).
void revisarHorario() {
  tm t;
  if (!leerHoraLocal(t)) return;

  int dia = diaIndice(t);
  if (dia < 0) return;

  char minutoActual[6];
  snprintf(minutoActual, sizeof(minutoActual), "%02d:%02d", t.tm_hour, t.tm_min);
  if (strcmp(minutoActual, minutoProcesado) == 0) return;
  strcpy(minutoProcesado, minutoActual);

  Horario &h = horarioVigente(t);
  for (int i = 0; i < h.cantidad; i++) {
    TimbreProgramado &tp = h.items[i];
    if ((tp.dias & (1 << dia)) == 0) continue;
    if (strcmp(tp.hora, minutoActual) != 0) continue;

    Serial.printf("[TIMBRE] automático: %s %s\n", tp.hora, tp.etiqueta);
    activarTimbre(tp.duracionSeg, tp.etiqueta);
    // RF-17: a la bitácora, con el id del timbre programado.
    encolarReporteActivacion("automatico", tp.id, tp.duracionSeg);
  }
}

// El próximo toque de hoy, para la pantalla (RF-25). Devuelve false si ya no
// queda ninguno.
bool proximoTimbre(const tm &t, TimbreProgramado &salida) {
  int dia = diaIndice(t);
  if (dia < 0) return false;

  char ahora[6];
  snprintf(ahora, sizeof(ahora), "%02d:%02d", t.tm_hour, t.tm_min);

  Horario &h = horarioVigente(const_cast<tm &>(t));
  bool hallado = false;
  for (int i = 0; i < h.cantidad; i++) {
    TimbreProgramado &tp = h.items[i];
    if ((tp.dias & (1 << dia)) == 0) continue;
    if (strcmp(tp.hora, ahora) < 0) continue;  // ya pasó
    if (!hallado || strcmp(tp.hora, salida.hora) < 0) {
      salida = tp;
      hallado = true;
    }
  }
  return hallado;
}

// ============================================================
// 6. Timbre (relé)
// ============================================================

void activarTimbre(uint8_t duracionSeg, const char *motivo) {
  digitalWrite(PIN_RELE, HIGH);
  timbreActivo = true;
  timbreHasta = millis() + (unsigned long)duracionSeg * 1000UL;
  strlcpy(timbreMotivo, motivo, sizeof(timbreMotivo));
  dibujarPantalla();  // RF-26: el indicador aparece de inmediato
}

// ============================================================
// 7. Botón físico (RF-15)
// ============================================================

void atenderBoton() {
  static unsigned long ultimaPulsacion = 0;
  static bool estadoAnterior = HIGH;

  bool estado = digitalRead(PIN_BOTON);
  // Flanco de bajada + 400 ms de guarda contra rebotes y dedos ansiosos.
  if (estadoAnterior == HIGH && estado == LOW && millis() - ultimaPulsacion > 400) {
    ultimaPulsacion = millis();
    Serial.println("[TIMBRE] botón físico");
    activarTimbre(5, "Manual");
    encolarReporteActivacion("manual_fisico", nullptr, 5);  // RF-17
  }
  estadoAnterior = estado;
}

// ============================================================
// 8. Sismo (MPU-6050) — RF-18, RF-19, RF-22
// ============================================================

const uint8_t MPU_DIR = 0x68;

void iniciarMPU() {
  // Despertar el sensor y ponerlo en rango ±8g (4096 unidades por g).
  Wire.beginTransmission(MPU_DIR);
  Wire.write(0x6B); Wire.write(0x00);
  bool ok = (Wire.endTransmission() == 0);
  Wire.beginTransmission(MPU_DIR);
  Wire.write(0x1C); Wire.write(0x10);
  Wire.endTransmission();
  Serial.println(ok ? "[MPU] listo" : "[MPU] no responde");
}

// Lee la magnitud de la aceleración en g, o -1 si el sensor no contesta.
float leerAceleracionG() {
  Wire.beginTransmission(MPU_DIR);
  Wire.write(0x3B);
  if (Wire.endTransmission(false) != 0) return -1;
  if (Wire.requestFrom((int)MPU_DIR, 6) != 6) return -1;

  int16_t ax = (Wire.read() << 8) | Wire.read();
  int16_t ay = (Wire.read() << 8) | Wire.read();
  int16_t az = (Wire.read() << 8) | Wire.read();

  float x = ax / 4096.0f, y = ay / 4096.0f, z = az / 4096.0f;
  return sqrtf(x * x + y * y + z * z);
}

// Cómo se distingue un sismo de un camión (RF-19), en palabras simples:
//
//  · Un golpe o un camión pasando sacude fuerte pero POCO TIEMPO: picos
//    sueltos de menos de medio segundo.
//  · Un sismo sacude de forma SOSTENIDA: la vibración supera el umbral una y
//    otra vez durante más de `sismoDuracionMinMs` milisegundos.
//
//  Por eso el detector no mira un pico, mira la HISTORIA: cuándo empezó la
//  agitación, cuánto lleva, y qué fracción de las muestras del episodio
//  estuvo agitada. Solo si dura lo suficiente Y fue agitación continua
//  (>40% de muestras activas) se declara sismo.
unsigned long sismoInicio = 0;        // cuándo empezó el episodio
unsigned long sismoUltimaActividad = 0;
int sismoMuestrasTotal = 0;
int sismoMuestrasActivas = 0;
float sismoPicoG = 0;
unsigned long sismoUltimoEvento = 0;  // guarda de 60 s entre eventos

void muestrearSismo() {
  float mag = leerAceleracionG();
  if (mag < 0) return;

  // En reposo la magnitud es 1g (la gravedad); lo que importa es el exceso.
  float exceso = fabsf(mag - 1.0f);
  bool agitada = exceso > umbralSismicoG;
  unsigned long ahora = millis();

  if (sismoInicio == 0) {
    if (!agitada) return;
    // Arranca un episodio de vibración.
    sismoInicio = ahora;
    sismoUltimaActividad = ahora;
    sismoMuestrasTotal = 0;
    sismoMuestrasActivas = 0;
    sismoPicoG = 0;
  }

  sismoMuestrasTotal++;
  if (agitada) {
    sismoUltimaActividad = ahora;
    sismoMuestrasActivas++;
    if (exceso > sismoPicoG) sismoPicoG = exceso;
  }

  // 300 ms sin actividad = el episodio terminó; toca evaluarlo.
  if (ahora - sismoUltimaActividad < 300) return;

  unsigned long duracionMs = sismoUltimaActividad - sismoInicio;
  float fraccionActiva = sismoMuestrasTotal > 0
      ? (float)sismoMuestrasActivas / sismoMuestrasTotal : 0;
  bool esSismo = duracionMs >= (unsigned long)sismoDuracionMinMs
      && fraccionActiva > 0.4f
      && (ahora - sismoUltimoEvento) > 60000UL;

  if (esSismo) {
    sismoUltimoEvento = ahora;
    Serial.printf("[SISMO] %.2f g durante %lu ms\n", sismoPicoG, duracionMs);
    // RF-22: la alarma suena YA, sin preguntarle a nadie. 30 s de evacuación.
    activarTimbre(30, "SISMO");
    encolarReporteSismo(sismoPicoG, duracionMs);
  }

  sismoInicio = 0;  // listo para el próximo episodio
}

// ============================================================
// 9. Red: hablar con el backend Vapor
// ============================================================

void conectarWifi() {
  if (WiFi.status() == WL_CONNECTED) return;
  Serial.printf("[WIFI] conectando a %s...\n", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  // Espera corta y acotada: si no conecta, el loop lo reintenta en 10 s y
  // mientras tanto el timbre sigue operando offline (RF-31).
  for (int i = 0; i < 20 && WiFi.status() != WL_CONNECTED; i++) delay(250);
  Serial.println(WiFi.status() == WL_CONNECTED ? "[WIFI] conectado" : "[WIFI] sin conexión");
}

// GET con la llave del dispositivo. Devuelve el código HTTP y deja el cuerpo
// en `respuesta`.
int httpGet(const char *ruta, String &respuesta) {
  HTTPClient http;
  http.setTimeout(4000);
  http.begin(String(API_BASE) + ruta);
  http.addHeader("X-Device-Key", DEVICE_API_KEY);
  int codigo = http.GET();
  if (codigo > 0) respuesta = http.getString();
  http.end();
  return codigo;
}

int httpPost(const char *ruta, const String &cuerpo) {
  HTTPClient http;
  http.setTimeout(4000);
  http.begin(String(API_BASE) + ruta);
  http.addHeader("X-Device-Key", DEVICE_API_KEY);
  http.addHeader("Content-Type", "application/json");
  int codigo = http.POST(cuerpo);
  http.end();
  return codigo;
}

// Copia un arreglo de timbres del JSON al struct Horario.
void copiarTimbres(JsonArray fuente, Horario &destino) {
  destino.cantidad = 0;
  for (JsonObject t : fuente) {
    if (destino.cantidad >= MAX_TIMBRES) break;
    TimbreProgramado &tp = destino.items[destino.cantidad++];
    strlcpy(tp.id, t["id"] | "", sizeof(tp.id));
    strlcpy(tp.etiqueta, t["etiqueta"] | "", sizeof(tp.etiqueta));
    strlcpy(tp.hora, t["hora"] | "00:00", sizeof(tp.hora));
    tp.duracionSeg = t["duracionSeg"] | 5;
    tp.dias = 0;
    // "lunes".."sabado" → bits 0..5, en el mismo orden que diaIndice().
    const char *nombres[6] = {"lunes", "martes", "miercoles", "jueves", "viernes", "sabado"};
    for (JsonVariant d : t["dias"].as<JsonArray>()) {
      for (int i = 0; i < 6; i++) {
        if (strcmp(d.as<const char *>(), nombres[i]) == 0) tp.dias |= (1 << i);
      }
    }
  }
}

// RF-28: baja el horario completo y lo deja en flash. También trae la
// calibración sísmica y la hora del servidor (por si no hay NTP).
void sincronizarHorario() {
  tUltimaSync = millis();
  String cuerpo;
  int codigo = httpGet("/dispositivo/horario", cuerpo);
  if (codigo != 200) {
    Serial.printf("[SYNC] falló (%d); sigo con el horario en flash\n", codigo);
    return;
  }

  JsonDocument doc;
  if (deserializeJson(doc, cuerpo) != DeserializationError::Ok) {
    Serial.println("[SYNC] JSON inválido");
    return;
  }

  umbralSismicoG = doc["umbralSismicoG"] | 1.2f;
  sismoDuracionMinMs = doc["sismoDuracionMinMs"] | 800;

  copiarTimbres(doc["habitual"].as<JsonArray>(), habitual);

  hayEspecial = !doc["especial"].isNull();
  if (hayEspecial) {
    JsonObject e = doc["especial"];
    strlcpy(especialNombre, e["nombre"] | "", sizeof(especialNombre));
    strlcpy(especialInicio, e["fechaInicio"] | "", sizeof(especialInicio));
    strlcpy(especialFin, e["fechaFin"] | "", sizeof(especialFin));
    copiarTimbres(e["timbres"].as<JsonArray>(), especial);
  }

  if (!horaValida) {
    fijarHoraDelServidor(doc["fechaServidor"] | "", doc["horaServidor"] | "");
  }

  // El mismo JSON del servidor se guarda tal cual: una sola forma del dato.
  File f = LittleFS.open("/horario.json", "w");
  if (f) {
    f.print(cuerpo);
    f.close();
  }
  Serial.printf("[SYNC] %d timbres habituales%s\n", habitual.cantidad,
                hayEspecial ? " + horario especial" : "");
}

// Arranque sin red: el último horario sincronizado sale de la flash (RF-28).
void cargarHorarioDeFlash() {
  File f = LittleFS.open("/horario.json", "r");
  if (!f) {
    Serial.println("[FS] sin horario guardado todavía");
    return;
  }
  JsonDocument doc;
  DeserializationError err = deserializeJson(doc, f);
  f.close();
  if (err != DeserializationError::Ok) return;

  umbralSismicoG = doc["umbralSismicoG"] | 1.2f;
  sismoDuracionMinMs = doc["sismoDuracionMinMs"] | 800;
  copiarTimbres(doc["habitual"].as<JsonArray>(), habitual);
  hayEspecial = !doc["especial"].isNull();
  if (hayEspecial) {
    JsonObject e = doc["especial"];
    strlcpy(especialNombre, e["nombre"] | "", sizeof(especialNombre));
    strlcpy(especialInicio, e["fechaInicio"] | "", sizeof(especialInicio));
    strlcpy(especialFin, e["fechaFin"] | "", sizeof(especialFin));
    copiarTimbres(e["timbres"].as<JsonArray>(), especial);
  }
  Serial.printf("[FS] horario cargado: %d timbres\n", habitual.cantidad);
}

// RNF-04: ¿la app dejó una orden de timbre? Esta consulta corre cada 2 s y
// además le sirve al servidor como latido de "módulo en línea".
void consultarComandos() {
  String cuerpo;
  if (httpGet("/dispositivo/comandos", cuerpo) != 200) return;

  JsonDocument doc;
  if (deserializeJson(doc, cuerpo) != DeserializationError::Ok) return;

  if (doc["timbrar"] | false) {
    int duracion = doc["duracionSeg"] | 5;
    Serial.println("[TIMBRE] orden desde la app");
    // No se reporta: el backend ya registró la activación manual_app al
    // emitir la orden. Reportarla aquí la duplicaría.
    activarTimbre(duracion, "Desde la app");
  }
}

// ============================================================
// 10. Cola de reportes (RF-17 + RF-30)
// ============================================================
//
// Cada evento se escribe primero en `/reportes.jsonl` (una línea por evento,
// con su millis()). El envío lee la cola y borra lo enviado; si no hay red,
// la cola simplemente espera. Así el reporte sobrevive a cortes de luz e
// internet, y `ocurridoHaceSeg` viaja calculado con el reloj del módulo.

void encolarLinea(const String &linea) {
  File f = LittleFS.open("/reportes.jsonl", "a");
  if (!f) return;
  f.println(linea);
  f.close();
  // Intento inmediato: con red, el reporte llega en el acto.
  if (enLinea) enviarReportesPendientes();
}

void encolarReporteActivacion(const char *tipo, const char *timbreId, int duracionSeg) {
  JsonDocument doc;
  doc["clase"] = "activacion";
  doc["t"] = millis();
  doc["tipo"] = tipo;
  if (timbreId && timbreId[0] != '\0') doc["horarioTimbreId"] = timbreId;
  doc["duracionSeg"] = duracionSeg;
  String linea;
  serializeJson(doc, linea);
  encolarLinea(linea);
}

void encolarReporteSismo(float intensidadG, unsigned long duracionMs) {
  JsonDocument doc;
  doc["clase"] = "sismo";
  doc["t"] = millis();
  doc["intensidadG"] = intensidadG;
  doc["duracionMs"] = duracionMs;
  String linea;
  serializeJson(doc, linea);
  encolarLinea(linea);
}

void enviarReportesPendientes() {
  File f = LittleFS.open("/reportes.jsonl", "r");
  if (!f) return;

  String pendientes = "";
  bool huboFallo = false;

  while (f.available()) {
    String linea = f.readStringUntil('\n');
    linea.trim();
    if (linea.isEmpty()) continue;

    if (huboFallo) {
      pendientes += linea + "\n";
      continue;
    }

    JsonDocument doc;
    if (deserializeJson(doc, linea) != DeserializationError::Ok) continue;

    // Cuánto hace que ocurrió, según el reloj del módulo. Si millis() dio la
    // vuelta (49 días) o el evento es de antes de un reinicio, se manda 0:
    // mejor un timestamp aproximado que perder la bitácora.
    unsigned long t = doc["t"] | 0UL;
    unsigned long haceMs = (millis() >= t) ? millis() - t : 0;
    doc["ocurridoHaceSeg"] = haceMs / 1000;

    const char *clase = doc["clase"] | "";
    doc.remove("clase");
    doc.remove("t");

    String cuerpo;
    serializeJson(doc, cuerpo);
    const char *ruta = (strcmp(clase, "sismo") == 0)
        ? "/dispositivo/sismos" : "/dispositivo/activaciones";

    int codigo = httpPost(ruta, cuerpo);
    if (codigo != 201) {
      huboFallo = true;
      pendientes += linea + "\n";
    }
  }
  f.close();

  if (pendientes.isEmpty()) {
    LittleFS.remove("/reportes.jsonl");
  } else {
    File w = LittleFS.open("/reportes.jsonl", "w");
    if (w) {
      w.print(pendientes);
      w.close();
    }
  }
}

// ============================================================
// 11. Pantalla OLED (RF-24 a RF-27)
// ============================================================

void pantallaMensaje(const char *linea1, const char *linea2) {
  pantalla.clearBuffer();
  pantalla.setFont(u8g2_font_7x14B_tf);
  pantalla.drawStr(0, 24, linea1);
  pantalla.setFont(u8g2_font_6x12_tf);
  pantalla.drawStr(0, 44, linea2);
  pantalla.sendBuffer();
}

// Icono de "sin conexión" (RF-27): dos arcos de señal tachados, arriba a la
// derecha. Dibujado a mano para no depender de una fuente de iconos.
void dibujarIconoOffline() {
  int cx = 120, cy = 10;
  pantalla.drawDisc(cx, cy, 1);
  pantalla.drawCircle(cx, cy, 4, U8G2_DRAW_UPPER_LEFT);
  pantalla.drawCircle(cx, cy, 7, U8G2_DRAW_UPPER_LEFT);
  pantalla.drawLine(cx - 9, cy - 9, cx + 2, cy + 2);
}

void dibujarPantalla() {
  // RF-26: mientras suena, la pantalla entera es el indicador.
  if (timbreActivo) {
    pantalla.clearBuffer();
    pantalla.setFont(u8g2_font_10x20_tf);
    pantalla.drawStr(10, 30, "\xa1TIMBRE!");
    pantalla.setFont(u8g2_font_7x14_tf);
    pantalla.drawStr(10, 52, timbreMotivo);
    pantalla.sendBuffer();
    return;
  }

  pantalla.clearBuffer();

  tm t;
  if (!leerHoraLocal(t)) {
    pantalla.setFont(u8g2_font_7x14B_tf);
    pantalla.drawStr(0, 24, "Sin hora");
    pantalla.setFont(u8g2_font_6x12_tf);
    pantalla.drawStr(0, 44, "Esperando red...");
    if (!enLinea) dibujarIconoOffline();
    pantalla.sendBuffer();
    return;
  }

  // Hora actual, grande (RF-25).
  char hora[9];
  snprintf(hora, sizeof(hora), "%02d:%02d:%02d", t.tm_hour, t.tm_min, t.tm_sec);
  pantalla.setFont(u8g2_font_logisoso16_tf);
  pantalla.drawStr(0, 18, hora);

  if (!enLinea) dibujarIconoOffline();  // RF-27

  // Próximo timbre y tiempo restante (RF-25).
  TimbreProgramado proximo;
  if (proximoTimbre(t, proximo)) {
    pantalla.setFont(u8g2_font_6x12_tf);
    char linea[40];
    snprintf(linea, sizeof(linea), "Prox: %s %s", proximo.hora, proximo.etiqueta);
    pantalla.drawStr(0, 38, linea);

    int hh, mm;
    sscanf(proximo.hora, "%d:%d", &hh, &mm);
    int faltanSeg = (hh * 3600 + mm * 60) - (t.tm_hour * 3600 + t.tm_min * 60 + t.tm_sec);
    if (faltanSeg < 0) faltanSeg = 0;
    snprintf(linea, sizeof(linea), "Faltan %02d:%02d:%02d",
             faltanSeg / 3600, (faltanSeg % 3600) / 60, faltanSeg % 60);
    pantalla.drawStr(0, 52, linea);
  } else {
    pantalla.setFont(u8g2_font_6x12_tf);
    pantalla.drawStr(0, 38, "Sin mas timbres hoy");
  }

  // Si rige un horario especial, se dice abajo (RF-10).
  if (especialVigente(t)) {
    pantalla.setFont(u8g2_font_5x8_tf);
    char linea[40];
    snprintf(linea, sizeof(linea), "Especial: %s", especialNombre);
    pantalla.drawStr(0, 63, linea);
  }

  pantalla.sendBuffer();
}
