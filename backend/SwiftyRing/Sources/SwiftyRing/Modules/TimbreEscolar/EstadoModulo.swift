//
//  EstadoModulo.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  Estado en memoria del módulo físico ESP32: cuándo habló por última vez, si
//  hay una orden de timbre esperándolo y la conexión WebSocket persistente.
//
//  Vive en memoria y no en PostgreSQL a propósito: son datos de segundos de
//  vida y escribirlos en la base en cada consulta sería castigar el disco para
//  nada. Si el servidor se reinicia, lo único que se pierde es una orden de
//  timbre pendiente de un instante, el indicador "en línea" y la conexión
//  WebSocket (que el módulo restablece solo en segundos).
//

import Foundation
import Vapor

actor EstadoModulo {
    static let compartido = EstadoModulo()
    private var ultimoContacto: Date?
    private var ordenPendiente: Int?
    private var conexionWS: WebSocket?

    func registrarContacto() {
        ultimoContacto = Date()
    }

    func registrarConexion(_ ws: WebSocket) {
        conexionWS = ws
        ultimoContacto = Date()
    }

    func desregistrarConexion() {
        conexionWS = nil
    }

    func enLinea(margen: TimeInterval = 15) -> Bool {
        if let ws = conexionWS, !ws.isClosed {
            return true
        }
        guard let ultimoContacto else { return false }
        return Date().timeIntervalSince(ultimoContacto) < margen
    }

    func notificarSincronizacion(motivo: String? = nil) {
        if let ws = conexionWS, !ws.isClosed {
            if let motivo = motivo {
                ws.send("{\"tipo\":\"sincronizar\",\"motivo\":\"\(motivo)\"}")
            } else {
                ws.send("{\"tipo\":\"sincronizar\"}")
            }
        }
    }

    func notificarConfiguracion(
        modoUps: Bool,
        duracionManualSeg: Int,
        umbralSismicoG: Double? = nil,
        sismoDuracionMinMs: Int? = nil
    ) {
        if let ws = conexionWS, !ws.isClosed {
            var json = "{\"tipo\":\"config\",\"modoUps\":\(modoUps),\"duracionManualSeg\":\(duracionManualSeg)"
            if let umbral = umbralSismicoG {
                json += ",\"umbralSismicoG\":\(umbral)"
            }
            if let dur = sismoDuracionMinMs {
                json += ",\"sismoDuracionMinMs\":\(dur)"
            }
            json += "}"
            ws.send(json)
        }
    }

    func ordenarTimbre(duracionSeg: Int) {
        if let ws = conexionWS, !ws.isClosed {
            ws.send("{\"tipo\":\"timbrar\",\"duracionSeg\":\(duracionSeg)}")
        } else {
            ordenPendiente = duracionSeg
        }
    }

    func retirarOrden() -> Int? {
        defer { ordenPendiente = nil }
        return ordenPendiente
    }
}
