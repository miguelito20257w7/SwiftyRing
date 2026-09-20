//
//  enlace.h
//  SwiftyRing · firmware del módulo de timbre (ESP-IDF)
//
//  El enlace por radio entre los dos módulos, sin router de por medio
//  (ESP-NOW). Lo usan los dos roles, pero cada uno para algo distinto:
//
//   · El MAESTRO (ROL_ESCLAVO = 0) es el que habla con el servidor. Manda un
//     latido cada segundo con la hora y la versión del horario, le empuja el
//     horario al esclavo cuando cambia, y le ordena timbrar cuando alguien
//     pulsa el botón físico o la app manda la orden.
//
//   · El ESCLAVO (ROL_ESCLAVO = 1) no toca WiFi ni API: enciende la radio solo
//     para ESP-NOW, busca al maestro barriendo los canales, y con lo que recibe
//     pone su reloj y guarda el horario en SU propia flash. A partir de ahí
//     timbra por su cuenta, aunque el maestro se apague (RF-31).
//
//  Los dos, además, se avisan mutuamente cuando su acelerómetro siente una
//  sacudida: esa es la información con la que sismo.c decide si fue un sismo
//  de verdad o un camión (ver el comentario largo en sismo.c).
//
//  Reparto del trabajo entre tareas: la radio deja las tramas recibidas en una
//  cola y NO toca el relé ni la flash. Todo eso pasa en enlace_atender(), que
//  corre en el bucle de control, igual que hace red.c con sus órdenes.
//

#pragma once

#include <stdbool.h>
#include <stdint.h>

// Enciende ESP-NOW. En el esclavo además arranca la radio WiFi (sin conectarse
// a ninguna red). En el maestro se llama DESPUÉS de red_iniciar(), porque
// aprovecha el WiFi que ese ya dejó andando.
void enlace_iniciar(void);

// Se llama en cada vuelta del bucle de control: atiende lo que llegó por la
// radio, manda los latidos y, en el esclavo, busca el canal del maestro.
void enlace_atender(void);

// ¿Se ha oído al otro módulo hace poco? Si es false, cada nodo vuelve a
// decidir los sismos por su cuenta y la pantalla lo avisa.
bool enlace_pareja_viva(void);

// Le cuenta al otro nodo que este acelerómetro acaba de sentir una sacudida.
void enlace_avisar_sacudida(float pico_g, uint32_t duracion_ms);

// Le ordena al esclavo que timbre. Solo la usa el maestro, para que el botón
// físico y las órdenes de la app suenen también en el otro edificio. Los
// timbres del horario NO se mandan por aquí: el esclavo los tiene guardados y
// suena solo.
void enlace_ordenar_alarma(uint8_t duracion_seg, const char *motivo);
