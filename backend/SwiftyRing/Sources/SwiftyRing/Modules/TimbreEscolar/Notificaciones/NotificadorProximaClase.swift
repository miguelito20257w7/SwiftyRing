//
//  NotificadorProximaClase.swift
//  SwiftyRing · Modules/TimbreEscolar/Notificaciones
//
//  La regla de RF-36..RF-38 en un solo sitio: al sonar el timbre, calcular la
//  próxima clase de cada profesor, registrarla y enviársela al teléfono. La
//  usan tanto las activaciones desde la app como las que reporta el módulo
//  físico.
//
//  El registro en PostgreSQL y el envío por FCM son dos pasos separados a
//  propósito. El registro es la verdad del sistema y ocurre siempre; el envío
//  es un intento de entrega que puede fallar sin que se pierda nada: la
//  notificación queda con `enviada = false` y así se ve en el historial.
//

import Vapor
import Fluent
import Foundation

enum NotificadorProximaClase {

    /// Para cada profesor con clase a continuación, registra su notificación y
    /// se la envía. Devuelve cuántas se generaron. RF-38: sin clase siguiente,
    /// sin registro y sin aviso.
    @discardableResult
    static func generar(activacionID: UUID, on req: Request) async throws -> Int {
        let notificaciones = try await registrar(activacionID: activacionID, on: req.db)
        guard !notificaciones.isEmpty else { return 0 }

        await entregar(notificaciones, on: req)
        return notificaciones.count
    }

    // MARK: - Paso 1: calcular y registrar (RF-36)

    private static func registrar(
        activacionID: UUID,
        on db: any Database
    ) async throws -> [NotificacionProfesor] {
        guard let dia = FormatoTiempo.diaDeHoy() else { return [] }
        let horaActual = FormatoTiempo.horaActual()

        // Los horarios de salón de hoy…
        let horarios = try await HorarioSalon.query(on: db)
            .filter(\.$dia == dia)
            .filter(\.$activo == true)
            .all()
        guard !horarios.isEmpty else { return [] }

        let horarioIDs = try horarios.map { try $0.requireID() }
        let salonPorHorario = Dictionary(uniqueKeysWithValues: try horarios.map { (try $0.requireID(), $0.salonID) })

        // …sus bloques que aún no empiezan, ordenados: el primero de cada
        // profesor es su "próxima clase" (RF-36).
        let bloques = try await Bloque.query(on: db)
            .filter(\.$horarioSalon.$id ~~ horarioIDs)
            .filter(\.$horaInicio >= horaActual)
            .sort(\.$horaInicio)
            .all()
        guard !bloques.isEmpty else { return [] }

        var proximoPorProfesor: [UUID: Bloque] = [:]
        for bloque in bloques where proximoPorProfesor[bloque.profesorID] == nil {
            proximoPorProfesor[bloque.profesorID] = bloque
        }

        let materias = try await Materia.query(on: db).all()
        let materiaPorID = Dictionary(uniqueKeysWithValues: try materias.map { (try $0.requireID(), $0.nombre) })
        let salones = try await Salon.query(on: db).all()
        let salonNombrePorID = Dictionary(uniqueKeysWithValues: try salones.map { (try $0.requireID(), $0.nombre) })

        var creadas: [NotificacionProfesor] = []
        for (profesorID, bloque) in proximoPorProfesor {
            let materia = materiaPorID[bloque.materiaID] ?? "Clase"
            let salon = salonPorHorario[bloque.$horarioSalon.id].flatMap { salonNombrePorID[$0] } ?? "salón"
            // RF-37: hora, materia y salón.
            let notificacion = NotificacionProfesor(
                activacionID: activacionID,
                profesorID: profesorID,
                bloqueID: try bloque.requireID(),
                mensaje: "Próxima clase \(bloque.horaInicio): \(materia) en \(salon)"
            )
            try await notificacion.create(on: db)
            creadas.append(notificacion)
        }

        return creadas
    }

    // MARK: - Paso 2: entregar por push (RF-37)

    /// Envía cada notificación a los dispositivos de su profesor.
    ///
    /// Los envíos salen todos a la vez y las escrituras en la base van después,
    /// ya en serie. Ese orden no es capricho: RNF-05 da cinco segundos para
    /// avisarle a toda la planta docente, y encadenar una petición HTTP por
    /// profesor no cabría en ese plazo.
    private static func entregar(_ notificaciones: [NotificacionProfesor], on req: Request) async {
        guard await EnviadorFCM.compartido.estaConfigurado else { return }

        let profesorIDs = notificaciones.map(\.profesorID)
        guard let dispositivos = try? await Dispositivo.query(on: req.db)
            .filter(\.$usuarioID ~~ profesorIDs)
            .filter(\.$activo == true)
            .all()
        else { return }

        // Un profesor puede tener celular y tableta: el aviso va a todos sus
        // dispositivos activos.
        var tokensPorProfesor: [UUID: [String]] = [:]
        for dispositivo in dispositivos {
            tokensPorProfesor[dispositivo.usuarioID, default: []].append(dispositivo.fcmToken)
        }

        var resultados: [(NotificacionProfesor, EnviadorFCM.Resultado)] = []
        await withTaskGroup(of: (NotificacionProfesor, EnviadorFCM.Resultado).self) { grupo in
            for notificacion in notificaciones {
                guard let tokens = tokensPorProfesor[notificacion.profesorID], !tokens.isEmpty else { continue }
                grupo.addTask {
                    let resultado = await EnviadorFCM.compartido.enviar(
                        a: tokens,
                        titulo: "Tu próxima clase",
                        cuerpo: notificacion.mensaje,
                        // Con esto la app sabe abrir directo en el horario.
                        datos: ["tipo": "proxima_clase"],
                        client: req.client,
                        logger: req.logger
                    )
                    return (notificacion, resultado)
                }
            }
            for await par in grupo {
                resultados.append(par)
            }
        }

        var tokensMuertos: [String] = []
        for (notificacion, resultado) in resultados {
            tokensMuertos.append(contentsOf: resultado.muertos)
            guard resultado.huboEntrega else { continue }
            notificacion.enviada = true
            notificacion.enviadaAt = Date()
            try? await notificacion.save(on: req.db)
        }

        await Dispositivos.desactivar(tokensMuertos, on: req)
    }
}

// MARK: - Higiene de dispositivos

enum Dispositivos {
    /// Desactiva los dispositivos cuyo token FCM ya no existe (app
    /// desinstalada, token rotado). Sin esto, cada timbre volvería a intentar
    /// entregar a teléfonos que nunca van a responder.
    static func desactivar(_ tokens: [String], on req: Request) async {
        guard !tokens.isEmpty else { return }
        do {
            try await Dispositivo.query(on: req.db)
                .filter(\.$fcmToken ~~ tokens)
                .set(\.$activo, to: false)
                .update()
            req.logger.info("FCM: \(tokens.count) dispositivo(s) desactivado(s) por token inválido")
        } catch {
            req.logger.report(error: error)
        }
    }
}
