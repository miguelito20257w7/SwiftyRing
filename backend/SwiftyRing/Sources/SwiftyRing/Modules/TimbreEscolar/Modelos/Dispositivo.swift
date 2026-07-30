//
//  Dispositivo.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  Dispositivos de cada usuario y su token FCM. El push se manda a TODOS los
//  dispositivos activos del usuario, no a "el" dispositivo.
//

import Fluent
import Foundation

final class Dispositivo: Model, @unchecked Sendable {
    static let schema = "dispositivos"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "usuario_id")
    var usuarioID: UUID

    @Enum(key: "plataforma")
    var plataforma: Plataforma

    /// Token FCM del dispositivo, destino de las notificaciones push. Único:
    /// si el mismo token vuelve a registrarse (reinstalación), se actualiza el
    /// registro existente en vez de duplicarlo.
    @Field(key: "fcm_token")
    var fcmToken: String

    @OptionalField(key: "nombre_dispositivo")
    var nombreDispositivo: String?

    @Field(key: "activo")
    var activo: Bool

    @Timestamp(key: "registrado_at", on: .create)
    var registradoAt: Date?

    @OptionalField(key: "ultimo_uso_at")
    var ultimoUsoAt: Date?

    init() { }

    init(
        usuarioID: UUID,
        plataforma: Plataforma,
        fcmToken: String,
        nombreDispositivo: String? = nil,
        activo: Bool = true
    ) {
        self.usuarioID = usuarioID
        self.plataforma = plataforma
        self.fcmToken = fcmToken
        self.nombreDispositivo = nombreDispositivo
        self.activo = activo
    }
}
