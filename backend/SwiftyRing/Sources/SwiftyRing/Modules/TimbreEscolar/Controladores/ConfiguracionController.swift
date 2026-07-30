//
//  ConfiguracionController.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  Parámetros globales del sistema (F-07): nombre del colegio y calibración
//  del detector sísmico (RF-19). Solo administrador.
//

import Vapor
import Fluent

struct ConfiguracionDTO: Content {
    let nombreColegio: String?
    let umbralSismicoG: Double
    let sismoDuracionMinMs: Int
    let modoOffline: Bool
    /// ¿El módulo ESP32 se ha reportado en los últimos segundos? Sale del
    /// latido en memoria (`EstadoModulo`), no de la base de datos.
    let moduloEnLinea: Bool
    /// Última descarga del horario por parte del módulo (RF-30).
    let ultimaSync: Date?

    init(_ config: ConfiguracionSistema, moduloEnLinea: Bool) {
        self.nombreColegio = config.nombreColegio
        self.umbralSismicoG = config.umbralSismicoG
        self.sismoDuracionMinMs = config.sismoDuracionMinMs
        self.modoOffline = config.modoOffline
        self.moduloEnLinea = moduloEnLinea
        self.ultimaSync = config.ultimaSync
    }
}

struct GuardarConfiguracionRequest: Content {
    let nombreColegio: String?
    let umbralSismicoG: Double
    let sismoDuracionMinMs: Int
}

struct ConfiguracionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let config = routes.grouped("api")
            .grouped(SwiftyRingAuthMiddleware())
            .grouped("configuracion")

        config.get(use: leer)
        config.put(use: guardar)
    }

    func leer(req: Request) async throws -> ConfiguracionDTO {
        try req.exigirRol(.admin)
        return ConfiguracionDTO(
            try await ConfiguracionSistema.actual(on: req.db),
            moduloEnLinea: await EstadoModulo.compartido.enLinea()
        )
    }

    func guardar(req: Request) async throws -> ConfiguracionDTO {
        try req.exigirRol(.admin)
        let datos = try req.content.decode(GuardarConfiguracionRequest.self)

        // Los límites vienen del rango físico del MPU-6050 y de lo que tiene
        // sentido como sismo: fuera de esto es un error de tipeo, no una
        // calibración.
        guard (0.1...16.0).contains(datos.umbralSismicoG) else {
            throw Abort(.badRequest, reason: "El umbral sísmico debe estar entre 0.1 y 16 g")
        }
        guard (100...60_000).contains(datos.sismoDuracionMinMs) else {
            throw Abort(.badRequest, reason: "La duración mínima debe estar entre 100 y 60000 ms")
        }

        let config = try await ConfiguracionSistema.actual(on: req.db)
        config.nombreColegio = datos.nombreColegio?.vacioComoNil()
        config.umbralSismicoG = datos.umbralSismicoG
        config.sismoDuracionMinMs = datos.sismoDuracionMinMs
        try await config.save(on: req.db)

        return ConfiguracionDTO(
            config,
            moduloEnLinea: await EstadoModulo.compartido.enLinea()
        )
    }
}
