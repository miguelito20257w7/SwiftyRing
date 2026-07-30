//
//  ConfiguracionSistema.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  Parámetros globales del sistema en fila única (F-07). La PK es el texto
//  fijo "config": no hay segunda fila posible.
//

import Fluent
import Foundation

final class ConfiguracionSistema: Model, @unchecked Sendable {
    static let schema = "configuracion_sistema"

    /// Siempre `"config"`. Se asigna en el seed, nunca se genera.
    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @OptionalField(key: "nombre_colegio")
    var nombreColegio: String?

    /// Umbral de aceleración para considerar sismo, en g (RF-19).
    @Field(key: "umbral_sismico_g")
    var umbralSismicoG: Double

    /// Duración mínima de la vibración para considerarla sismo, en ms.
    @Field(key: "sismo_duracion_min_ms")
    var sismoDuracionMinMs: Int

    @Field(key: "modo_offline")
    var modoOffline: Bool

    @OptionalField(key: "ultima_sync")
    var ultimaSync: Date?

    init() { }

    init(
        nombreColegio: String? = nil,
        umbralSismicoG: Double = 1.2,
        sismoDuracionMinMs: Int = 800,
        modoOffline: Bool = false
    ) {
        self.id = "config"
        self.nombreColegio = nombreColegio
        self.umbralSismicoG = umbralSismicoG
        self.sismoDuracionMinMs = sismoDuracionMinMs
        self.modoOffline = modoOffline
    }

    /// La fila única, creándola con los valores por defecto si aún no existe.
    static func actual(on db: any Database) async throws -> ConfiguracionSistema {
        if let config = try await ConfiguracionSistema.find("config", on: db) {
            return config
        }
        let config = ConfiguracionSistema(nombreColegio: "I.E. Santa Sofía")
        try await config.create(on: db)
        return config
    }
}
