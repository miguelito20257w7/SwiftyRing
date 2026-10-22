//
//  HorarioTimbre.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  Timbres del horario habitual semanal (RF-07..RF-09) y los días en que
//  suena cada uno.
//
//  Sobre el tipo de `hora`: el modelo de datos la define como `time` de
//  PostgreSQL, pero Fluent no ofrece un mapeo directo de ese tipo. Se guarda
//  como texto `"HH:mm"` (cero-padded), que ordena y compara igual que un time
//  y viaja tal cual en el JSON hacia la app.
//

import Fluent
import Foundation

final class HorarioTimbre: Model, @unchecked Sendable {
    static let schema = "horario_timbres"

    @ID(key: .id)
    var id: UUID?

    /// Etiqueta descriptiva (ej. "Inicio de clases") (RF-08).
    @Field(key: "etiqueta")
    var etiqueta: String

    /// Hora exacta a la que suena, formato `"HH:mm"`.
    @Field(key: "hora")
    var hora: String

    /// Duración del sonido en segundos.
    @Field(key: "duracion_seg")
    var duracionSeg: Int

    /// Desactivar un timbre sin eliminarlo.
    @Field(key: "activo")
    var activo: Bool

    @Timestamp(key: "creado_at", on: .create)
    var creadoAt: Date?

    /// Soporte para eliminación suave (soft delete).
    @Timestamp(key: "deleted_at", on: .delete)
    var deletedAt: Date?

    @Children(for: \.$timbre)
    var dias: [TimbreDia]

    init() { }

    init(etiqueta: String, hora: String, duracionSeg: Int = 5, activo: Bool = true) {
        self.etiqueta = etiqueta
        self.hora = hora
        self.duracionSeg = duracionSeg
        self.activo = activo
    }
}

/// Día de la semana en que suena un timbre habitual (RF-08). Un timbre no
/// puede repetir día: restricción única `(timbre_id, dia)`.
final class TimbreDia: Model, @unchecked Sendable {
    static let schema = "timbre_dias"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "timbre_id")
    var timbre: HorarioTimbre

    @Enum(key: "dia")
    var dia: DiaSemana

    init() { }

    init(timbreID: UUID, dia: DiaSemana) {
        self.$timbre.id = timbreID
        self.dia = dia
    }
}
