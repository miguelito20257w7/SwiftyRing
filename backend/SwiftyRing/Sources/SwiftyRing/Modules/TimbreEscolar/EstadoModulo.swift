//
//  EstadoModulo.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  Estado en memoria del módulo físico ESP32: cuándo habló por última vez y si
//  hay una orden de timbre esperándolo.
//
//  Vive en memoria y no en PostgreSQL a propósito: son datos de segundos de
//  vida (el módulo consulta cada ~2 s, RNF-04) y escribirlos en la base en
//  cada consulta sería castigar el disco para nada. Si el servidor se
//  reinicia, lo único que se pierde es una orden de timbre pendiente de un
//  instante y el indicador "en línea" durante los segundos que tarda el
//  módulo en volver a reportarse. La bitácora real (RF-17) sí va a la base.
//

import Foundation

actor EstadoModulo {

    static let compartido = EstadoModulo()

    /// Última vez que el módulo consultó al servidor.
    private var ultimoContacto: Date?

    /// Orden de timbre manual pendiente de entregar, con su duración en
    /// segundos. Solo cabe una: dos toques seguidos suenan como uno.
    private var ordenPendiente: Int?

    /// El módulo acaba de hablar con el servidor.
    func registrarContacto() {
        ultimoContacto = Date()
    }

    /// ¿El módulo se ha reportado hace poco? El margen cubre varios ciclos de
    /// consulta: una sola petición perdida no debe marcarlo offline.
    func enLinea(margen: TimeInterval = 15) -> Bool {
        guard let ultimoContacto else { return false }
        return Date().timeIntervalSince(ultimoContacto) < margen
    }

    /// RF-14/RF-16: la app ordenó timbrar; el módulo la recogerá en su
    /// siguiente consulta (menos de 2 s con conexión estable, RNF-04).
    func ordenarTimbre(duracionSeg: Int) {
        ordenPendiente = duracionSeg
    }

    /// Entrega la orden pendiente (si la hay) y la retira: una orden suena
    /// una sola vez.
    func retirarOrden() -> Int? {
        defer { ordenPendiente = nil }
        return ordenPendiente
    }
}
