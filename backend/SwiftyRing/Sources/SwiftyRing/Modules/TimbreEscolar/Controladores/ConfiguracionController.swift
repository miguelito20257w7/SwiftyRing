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
    let modoUps: Bool
    let duracionTimbreManualSeg: Int
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
        self.modoUps = config.modoUps
        self.duracionTimbreManualSeg = config.duracionTimbreManualSeg
        self.moduloEnLinea = moduloEnLinea
        self.ultimaSync = config.ultimaSync
    }
}

struct GuardarConfiguracionRequest: Content {
    let nombreColegio: String?
    let umbralSismicoG: Double
    let sismoDuracionMinMs: Int
    let modoUps: Bool?
    let duracionTimbreManualSeg: Int?
}

/// Lo que del sistema puede ver **cualquier usuario con sesión** (F-09): de
/// qué colegio es la instalación y si el módulo físico está respondiendo.
///
/// Existe separado de [ConfiguracionDTO] porque la calibración sísmica es
/// materia de administración: el profesor no la ajusta y no tiene por qué
/// verla. Abrir el endpoint de admin habría sido una línea menos y un dato
/// de más.
struct ResumenSistemaDTO: Content {
    let nombreColegio: String?
    let moduloEnLinea: Bool
    let ultimaSync: Date?
}

struct ConfiguracionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let config = routes.grouped("api")
            .grouped(SwiftyRingAuthMiddleware())
            .grouped("configuracion")

        config.get(use: leer)
        config.put(use: guardar)
        config.get("resumen", use: resumen)
    }

    /// F-09: el resumen que ve el profesor en sus ajustes. Basta con tener
    /// sesión; no se exige rol porque no hay nada aquí que un usuario
    /// autenticado no pueda saber de su propio colegio.
    func resumen(req: Request) async throws -> ResumenSistemaDTO {
        _ = try req.requireSwiftyRingPayload()
        let config = try await ConfiguracionSistema.actual(on: req.db)
        return ResumenSistemaDTO(
            nombreColegio: config.nombreColegio,
            moduloEnLinea: await EstadoModulo.compartido.enLinea(),
            ultimaSync: config.ultimaSync
        )
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
        guard (0.015...2.0).contains(datos.umbralSismicoG) else {
            throw Abort(.badRequest, reason: "El umbral sísmico debe estar entre 0.015 y 2.0 g")
        }
        guard (100...60_000).contains(datos.sismoDuracionMinMs) else {
            throw Abort(.badRequest, reason: "La duración mínima debe estar entre 100 y 60000 ms")
        }

        let config = try await ConfiguracionSistema.actual(on: req.db)

        let cambioUmbral = abs(datos.umbralSismicoG - config.umbralSismicoG) > 0.001
        let cambioSismoDur = (datos.sismoDuracionMinMs != config.sismoDuracionMinMs)

        var cambioDuracion = false
        if let duracion = datos.duracionTimbreManualSeg {
            guard (1...60).contains(duracion) else {
                throw Abort(.badRequest, reason: "La duración del timbre manual debe estar entre 1 y 60 segundos")
            }
            if duracion != config.duracionTimbreManualSeg {
                cambioDuracion = true
                config.duracionTimbreManualSeg = duracion
            }
        }

        var cambioUps = false
        if let modoUps = datos.modoUps {
            if modoUps != config.modoUps {
                cambioUps = true
                config.modoUps = modoUps
            }
        }

        config.nombreColegio = datos.nombreColegio?.vacioComoNil()
        config.umbralSismicoG = datos.umbralSismicoG
        config.sismoDuracionMinMs = datos.sismoDuracionMinMs

        try await config.save(on: req.db)

        req.logger.info("Configuración actualizada: umbral=\(cambioUmbral) (\(config.umbralSismicoG) g), sismoDur=\(cambioSismoDur) (\(config.sismoDuracionMinMs) ms), ups=\(cambioUps), durManual=\(cambioDuracion)")

        await EstadoModulo.compartido.notificarConfiguracion(
            modoUps: cambioUps ? config.modoUps : nil,
            duracionManualSeg: cambioDuracion ? config.duracionTimbreManualSeg : nil,
            umbralSismicoG: cambioUmbral ? config.umbralSismicoG : nil,
            sismoDuracionMinMs: cambioSismoDur ? config.sismoDuracionMinMs : nil
        )
        return ConfiguracionDTO(
            config,
            moduloEnLinea: await EstadoModulo.compartido.enLinea()
        )
    }
}
