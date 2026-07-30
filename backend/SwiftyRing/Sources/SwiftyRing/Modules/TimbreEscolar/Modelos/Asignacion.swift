//
//  Asignacion.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  Horario académico por salón: la cabecera (salón + día) y sus bloques de
//  clase (RF-34). Es la base de las notificaciones de próxima clase (RF-36).
//

import Fluent
import Foundation

/// Cabecera del horario de un salón para un día. Un salón solo puede tener un
/// horario por día: restricción única `(salon_id, dia)`.
final class HorarioSalon: Model, @unchecked Sendable {
    static let schema = "horario_salon"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "salon_id")
    var salonID: UUID

    @Enum(key: "dia")
    var dia: DiaSemana

    @Field(key: "activo")
    var activo: Bool

    @Children(for: \.$horarioSalon)
    var bloques: [Bloque]

    init() { }

    init(salonID: UUID, dia: DiaSemana, activo: Bool = true) {
        self.salonID = salonID
        self.dia = dia
        self.activo = activo
    }
}

final class Bloque: Model, @unchecked Sendable {
    static let schema = "bloques"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "horario_salon_id")
    var horarioSalon: HorarioSalon

    /// Orden del bloque dentro del día: 1, 2, 3…
    @Field(key: "numero")
    var numero: Int

    /// `"HH:mm"` (RF-34).
    @Field(key: "hora_inicio")
    var horaInicio: String

    @Field(key: "hora_fin")
    var horaFin: String

    @Field(key: "materia_id")
    var materiaID: UUID

    /// Profesor que atiende el bloque; base de las notificaciones (RF-36).
    @Field(key: "profesor_id")
    var profesorID: UUID

    init() { }

    init(
        horarioSalonID: UUID,
        numero: Int,
        horaInicio: String,
        horaFin: String,
        materiaID: UUID,
        profesorID: UUID
    ) {
        self.$horarioSalon.id = horarioSalonID
        self.numero = numero
        self.horaInicio = horaInicio
        self.horaFin = horaFin
        self.materiaID = materiaID
        self.profesorID = profesorID
    }
}
