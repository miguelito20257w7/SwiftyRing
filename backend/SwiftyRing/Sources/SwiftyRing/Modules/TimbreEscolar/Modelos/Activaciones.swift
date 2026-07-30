//
//  Activaciones.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  La bitácora del sistema: cada vez que suena el timbre (RF-17), los eventos
//  sísmicos que lo dispararon (RF-18..23) y las notificaciones de próxima
//  clase enviadas a los profesores (RF-36..38).
//

import Fluent
import Foundation

final class ActivacionTimbre: Model, @unchecked Sendable {
    static let schema = "activaciones_timbre"

    @ID(key: .id)
    var id: UUID?

    @Enum(key: "tipo")
    var tipo: TipoActivacion

    /// Usuario que activó el timbre; NULL si fue automático o sísmico.
    @OptionalField(key: "origen_usuario_id")
    var origenUsuarioID: UUID?

    @Field(key: "ocurrido_at")
    var ocurridoAt: Date

    /// Timbre programado que la originó, si fue automática.
    @OptionalField(key: "horario_timbre_id")
    var horarioTimbreID: UUID?

    @OptionalField(key: "duracion_seg")
    var duracionSeg: Int?

    init() { }

    init(
        tipo: TipoActivacion,
        origenUsuarioID: UUID? = nil,
        ocurridoAt: Date = Date(),
        horarioTimbreID: UUID? = nil,
        duracionSeg: Int? = nil
    ) {
        self.tipo = tipo
        self.origenUsuarioID = origenUsuarioID
        self.ocurridoAt = ocurridoAt
        self.horarioTimbreID = horarioTimbreID
        self.duracionSeg = duracionSeg
    }
}

final class EventoSismico: Model, @unchecked Sendable {
    static let schema = "eventos_sismicos"

    @ID(key: .id)
    var id: UUID?

    /// Activación de timbre generada por el evento (RF-22).
    @OptionalField(key: "activacion_id")
    var activacionID: UUID?

    /// Aceleración detectada, en unidades g (RF-21).
    @Field(key: "intensidad_g")
    var intensidadG: Double

    @Field(key: "duracion_ms")
    var duracionMs: Int

    @Field(key: "ocurrido_at")
    var ocurridoAt: Date

    @Field(key: "timbre_activado")
    var timbreActivado: Bool

    /// ¿Ya se notificó al administrador? (RF-20)
    @Field(key: "notificacion_enviada")
    var notificacionEnviada: Bool

    init() { }

    init(
        activacionID: UUID? = nil,
        intensidadG: Double,
        duracionMs: Int,
        ocurridoAt: Date = Date(),
        timbreActivado: Bool = true,
        notificacionEnviada: Bool = false
    ) {
        self.activacionID = activacionID
        self.intensidadG = intensidadG
        self.duracionMs = duracionMs
        self.ocurridoAt = ocurridoAt
        self.timbreActivado = timbreActivado
        self.notificacionEnviada = notificacionEnviada
    }
}

/// Notificación de próxima clase generada por una activación. Solo existe
/// registro si el profesor tiene clase en el siguiente período (RF-38).
final class NotificacionProfesor: Model, @unchecked Sendable {
    static let schema = "notificaciones_profesores"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "activacion_id")
    var activacionID: UUID

    @Field(key: "profesor_id")
    var profesorID: UUID

    @Field(key: "bloque_id")
    var bloqueID: UUID

    @Field(key: "mensaje")
    var mensaje: String

    /// `false` mientras FCM no confirme la entrega. El envío real por FCM es
    /// el único tramo pendiente de infraestructura externa.
    @Field(key: "enviada")
    var enviada: Bool

    @OptionalField(key: "enviada_at")
    var enviadaAt: Date?

    init() { }

    init(activacionID: UUID, profesorID: UUID, bloqueID: UUID, mensaje: String, enviada: Bool = false) {
        self.activacionID = activacionID
        self.profesorID = profesorID
        self.bloqueID = bloqueID
        self.mensaje = mensaje
        self.enviada = enviada
    }
}
