//
//  HorarioEspecial.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  Horarios especiales que suspenden temporalmente el habitual (RF-10..RF-13).
//
//  `fecha_inicio` / `fecha_fin` se guardan como texto ISO `"yyyy-MM-dd"` por la
//  misma razón que `hora` en HorarioTimbre: compara y ordena igual que un date
//  y no arrastra los problemas de zona horaria de un timestamptz.
//

import Fluent
import Foundation

final class HorarioEspecial: Model, @unchecked Sendable {
    static let schema = "horario_especial"

    @ID(key: .id)
    var id: UUID?

    /// Nombre descriptivo (ej. "Semana de exámenes").
    @Field(key: "nombre")
    var nombre: String

    /// Inicio de la vigencia, `"yyyy-MM-dd"` (RF-11).
    @Field(key: "fecha_inicio")
    var fechaInicio: String

    /// Fin de la vigencia; al vencer se retoma el horario habitual (RF-12).
    @Field(key: "fecha_fin")
    var fechaFin: String

    @Field(key: "activo")
    var activo: Bool

    /// Administrador que lo creó (RF-13).
    @Field(key: "creado_por")
    var creadoPor: UUID

    @Timestamp(key: "creado_at", on: .create)
    var creadoAt: Date?

    @Children(for: \.$horarioEspecial)
    var timbres: [TimbreEspecial]

    init() { }

    init(nombre: String, fechaInicio: String, fechaFin: String, creadoPor: UUID, activo: Bool = true) {
        self.nombre = nombre
        self.fechaInicio = fechaInicio
        self.fechaFin = fechaFin
        self.creadoPor = creadoPor
        self.activo = activo
    }

    /// ¿Está vigente en la fecha dada (`"yyyy-MM-dd"`)? La comparación de
    /// textos ISO equivale a la de fechas.
    func vigente(en fecha: String) -> Bool {
        activo && fechaInicio <= fecha && fecha <= fechaFin
    }
}

final class TimbreEspecial: Model, @unchecked Sendable {
    static let schema = "timbres_especiales"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "horario_especial_id")
    var horarioEspecial: HorarioEspecial

    @Field(key: "etiqueta")
    var etiqueta: String

    /// Hora exacta, `"HH:mm"`.
    @Field(key: "hora")
    var hora: String

    @Field(key: "duracion_seg")
    var duracionSeg: Int

    @Children(for: \.$timbreEspecial)
    var dias: [TimbreEspecialDia]

    init() { }

    init(horarioEspecialID: UUID, etiqueta: String, hora: String, duracionSeg: Int = 5) {
        self.$horarioEspecial.id = horarioEspecialID
        self.etiqueta = etiqueta
        self.hora = hora
        self.duracionSeg = duracionSeg
    }
}

/// Día en que suena un timbre especial. Restricción única `(timbre_especial_id, dia)`.
final class TimbreEspecialDia: Model, @unchecked Sendable {
    static let schema = "timbre_especial_dias"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "timbre_especial_id")
    var timbreEspecial: TimbreEspecial

    @Enum(key: "dia")
    var dia: DiaSemana

    init() { }

    init(timbreEspecialID: UUID, dia: DiaSemana) {
        self.$timbreEspecial.id = timbreEspecialID
        self.dia = dia
    }
}
