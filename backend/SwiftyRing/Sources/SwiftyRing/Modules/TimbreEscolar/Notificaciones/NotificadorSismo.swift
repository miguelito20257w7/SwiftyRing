//
//  NotificadorSismo.swift
//  SwiftyRing · Modules/TimbreEscolar/Notificaciones
//
//  Aviso al administrador cuando el módulo confirma un sismo (RF-20, RF-21).
//
//  Ojo con el orden de las cosas: para cuando este código corre, el timbre de
//  evacuación **ya sonó**. El ESP32 lo activa por su cuenta en el momento de
//  detectar el evento (RF-22) sin esperar respuesta del servidor, justamente
//  para que un corte de internet no deje al colegio sin alarma. Esta
//  notificación no dispara nada: es el registro que le llega a Doña Andrea
//  para que sepa qué pasó y a qué hora.
//

import Vapor
import Fluent
import Foundation

enum NotificadorSismo {

    /// Avisa a los administradores activos y marca el evento como notificado.
    static func avisar(_ evento: EventoSismico, on req: Request) async {
        guard await EnviadorFCM.compartido.estaConfigurado else { return }

        // RF-20: el aviso es para el administrador. Al operador y a los
        // profesores no les corresponde gestionar la emergencia.
        guard let admins = try? await Usuario.query(on: req.db)
            .filter(\.$rol == .admin)
            .filter(\.$activo == true)
            .all(),
              !admins.isEmpty
        else { return }

        let adminIDs = admins.compactMap { try? $0.requireID() }
        guard let dispositivos = try? await Dispositivo.query(on: req.db)
            .filter(\.$usuarioID ~~ adminIDs)
            .filter(\.$activo == true)
            .all(),
              !dispositivos.isEmpty
        else { return }

        // RF-21: hora del evento, intensidad estimada en g y duración.
        let hora = FormatoTiempo.horaActual(evento.ocurridoAt)
        let intensidad = String(format: "%.2f", evento.intensidadG)
        let segundos = String(format: "%.1f", Double(evento.duracionMs) / 1000)
        let cuerpo = evento.timbreActivado
            ? "\(hora) · \(intensidad) g durante \(segundos) s. El timbre de evacuación se activó."
            : "\(hora) · \(intensidad) g durante \(segundos) s."

        let resultado = await EnviadorFCM.compartido.enviar(
            a: dispositivos.map(\.fcmToken),
            titulo: "Sismo detectado",
            cuerpo: cuerpo,
            datos: [
                "tipo": "sismo",
                "intensidadG": intensidad,
                "duracionMs": String(evento.duracionMs),
            ],
            client: req.client,
            logger: req.logger
        )

        if resultado.huboEntrega {
            evento.notificacionEnviada = true
            try? await evento.save(on: req.db)
        }
        await Dispositivos.desactivar(resultado.muertos, on: req)
    }
}
