//
//  NotificadorProximaClase.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  La regla de RF-36..RF-38 en un solo sitio: al sonar el timbre, registrar
//  para cada profesor su próxima clase. La usan tanto las activaciones desde
//  la app como las que reporta el módulo físico.
//

import Vapor
import Fluent
import Foundation

enum NotificadorProximaClase {

    /// Para cada profesor con clase a continuación, registra su notificación.
    /// Devuelve cuántas se generaron. RF-38: sin clase siguiente, sin registro.
    static func generar(activacionID: UUID, on db: any Database) async throws -> Int {
        guard let dia = FormatoTiempo.diaDeHoy() else { return 0 }
        let horaActual = FormatoTiempo.horaActual()

        // Los horarios de salón de hoy…
        let horarios = try await HorarioSalon.query(on: db)
            .filter(\.$dia == dia)
            .filter(\.$activo == true)
            .all()
        guard !horarios.isEmpty else { return 0 }

        let horarioIDs = try horarios.map { try $0.requireID() }
        let salonPorHorario = Dictionary(uniqueKeysWithValues: try horarios.map { (try $0.requireID(), $0.salonID) })

        // …sus bloques que aún no empiezan, ordenados: el primero de cada
        // profesor es su "próxima clase" (RF-36).
        let bloques = try await Bloque.query(on: db)
            .filter(\.$horarioSalon.$id ~~ horarioIDs)
            .filter(\.$horaInicio >= horaActual)
            .sort(\.$horaInicio)
            .all()
        guard !bloques.isEmpty else { return 0 }

        var proximoPorProfesor: [UUID: Bloque] = [:]
        for bloque in bloques where proximoPorProfesor[bloque.profesorID] == nil {
            proximoPorProfesor[bloque.profesorID] = bloque
        }

        let materias = try await Materia.query(on: db).all()
        let materiaPorID = Dictionary(uniqueKeysWithValues: try materias.map { (try $0.requireID(), $0.nombre) })
        let salones = try await Salon.query(on: db).all()
        let salonNombrePorID = Dictionary(uniqueKeysWithValues: try salones.map { (try $0.requireID(), $0.nombre) })

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
        }

        return proximoPorProfesor.count
    }
}
