//
//  Profesor.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  Extensión 1:1 del usuario con rol profesor (RF-32) y su relación con las
//  materias que dicta.
//

import Fluent
import Foundation

/// Perfil docente. Su PK es el mismo id del `Usuario` (relación 1:1): un
/// profesor no existe sin cuenta, y suspender la cuenta lo saca del sistema
/// sin tocar esta tabla.
final class Profesor: Model, @unchecked Sendable {
    static let schema = "profesores"

    /// El id del usuario dueño del perfil. Se asigna a mano, nunca se genera.
    @ID(custom: "usuario_id", generatedBy: .user)
    var id: UUID?

    @Enum(key: "jornada")
    var jornada: Jornada

    /// Grupo que dirige (ej. "11B"); NULL si no es director. Es texto libre a
    /// propósito: los grupos como entidad pertenecen al schema `banos` del otro
    /// equipo y aquí no se referencian (ver SketchBD.dbml).
    @OptionalField(key: "director_de_grupo")
    var directorDeGrupo: String?

    @Timestamp(key: "creado_at", on: .create)
    var creadoAt: Date?

    init() { }

    init(usuarioID: UUID, jornada: Jornada, directorDeGrupo: String? = nil) {
        self.id = usuarioID
        self.jornada = jornada
        self.directorDeGrupo = directorDeGrupo
    }
}

/// Relación muchos-a-muchos profesor ↔ materia (RF-32).
///
/// El modelo lleva un `id` propio porque Fluent no soporta PK compuestas; la
/// pareja se protege con la restricción única `(profesor_id, materia_id)`.
final class ProfesorMateria: Model, @unchecked Sendable {
    static let schema = "profesor_materias"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "profesor_id")
    var profesorID: UUID

    @Field(key: "materia_id")
    var materiaID: UUID

    init() { }

    init(profesorID: UUID, materiaID: UUID) {
        self.profesorID = profesorID
        self.materiaID = materiaID
    }
}
