//
//  HorariosEspecialesController.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  Horarios especiales (RF-10..RF-13): suspenden temporalmente el habitual
//  durante un rango de fechas y expiran solos (RF-12). Acceso exclusivo del
//  administrador (RF-13), incluso para consultarlos: el resto de roles solo ve
//  su efecto en `/api/timbres/hoy`.
//

import Vapor
import Fluent

struct TimbreEspecialDTO: Content {
    let id: UUID
    let etiqueta: String
    let hora: String
    let duracionSeg: Int
    let dias: [DiaSemana]
}

struct HorarioEspecialDTO: Content {
    let id: UUID
    let nombre: String
    let fechaInicio: String
    let fechaFin: String
    let activo: Bool
    /// ¿Cubre la fecha de hoy? Lo calcula el servidor para que la app no
    /// dependa del reloj del teléfono.
    let vigente: Bool
    let timbres: [TimbreEspecialDTO]
}

struct GuardarTimbreEspecialRequest: Content {
    let etiqueta: String
    let hora: String
    let duracionSeg: Int?
    let dias: [DiaSemana]
}

struct GuardarHorarioEspecialRequest: Content {
    let nombre: String
    let fechaInicio: String
    let fechaFin: String
    let activo: Bool?
    let timbres: [GuardarTimbreEspecialRequest]
}

struct HorariosEspecialesController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let especiales = routes.grouped("api")
            .grouped(SwiftyRingAuthMiddleware())
            .grouped("horarios-especiales")

        especiales.get(use: listar)
        especiales.post(use: crear)
        especiales.put(":id", use: editar)
        especiales.delete(":id", use: eliminar)
    }

    func listar(req: Request) async throws -> [HorarioEspecialDTO] {
        try req.exigirRol(.admin)

        let hoy = FormatoTiempo.hoyISO()
        let horarios = try await HorarioEspecial.query(on: req.db)
            .with(\.$timbres) { $0.with(\.$dias) }
            .sort(\.$fechaInicio, .descending)
            .all()

        return try horarios.map { try dto(de: $0, hoy: hoy) }
    }

    /// RF-11: crear con su rango de vigencia y sus timbres anidados.
    func crear(req: Request) async throws -> HorarioEspecialDTO {
        let payload = try req.exigirRol(.admin)
        let datos = try req.content.decode(GuardarHorarioEspecialRequest.self)
        try validar(datos)

        guard let creadorID = payload.usuarioID else {
            throw Abort(.unauthorized, reason: "Sesión no válida")
        }

        let horario = HorarioEspecial(
            nombre: datos.nombre.trimmingCharacters(in: .whitespacesAndNewlines),
            fechaInicio: datos.fechaInicio,
            fechaFin: datos.fechaFin,
            creadoPor: creadorID,
            activo: datos.activo ?? true
        )

        try await req.db.transaction { db in
            try await horario.create(on: db)
            try await crearTimbres(datos.timbres, en: horario.requireID(), on: db)
        }

        await EstadoModulo.compartido.notificarSincronizacion(motivo: "especial")
        return try await recargar(horario.requireID(), on: req.db)
    }

    /// Edita cabecera y reemplaza los timbres completos (estado final del
    /// formulario, como en el resto de la API).
    func editar(req: Request) async throws -> HorarioEspecialDTO {
        try req.exigirRol(.admin)
        let datos = try req.content.decode(GuardarHorarioEspecialRequest.self)
        try validar(datos)

        guard let horario = try await HorarioEspecial.find(req.parameters.get("id"), on: req.db) else {
            throw Abort(.notFound, reason: "El horario especial no existe")
        }

        try await req.db.transaction { db in
            horario.nombre = datos.nombre.trimmingCharacters(in: .whitespacesAndNewlines)
            horario.fechaInicio = datos.fechaInicio
            horario.fechaFin = datos.fechaFin
            horario.activo = datos.activo ?? horario.activo
            try await horario.save(on: db)

            let horarioID = try horario.requireID()
            // Borrar los timbres borra sus días en cascada.
            try await TimbreEspecial.query(on: db)
                .filter(\.$horarioEspecial.$id == horarioID)
                .delete()
            try await crearTimbres(datos.timbres, en: horarioID, on: db)
        }

        await EstadoModulo.compartido.notificarSincronizacion(motivo: "especial")
        return try await recargar(horario.requireID(), on: req.db)
    }

    func eliminar(req: Request) async throws -> HTTPStatus {
        try req.exigirRol(.admin)
        guard let horario = try await HorarioEspecial.find(req.parameters.get("id"), on: req.db) else {
            throw Abort(.notFound, reason: "El horario especial no existe")
        }
        try await horario.delete(on: req.db)
        await EstadoModulo.compartido.notificarSincronizacion(motivo: "especial")
        return .noContent
    }

    // MARK: - Apoyo

    private func crearTimbres(
        _ timbres: [GuardarTimbreEspecialRequest],
        en horarioID: UUID,
        on db: any Database
    ) async throws {
        for timbre in timbres {
            let nuevo = TimbreEspecial(
                horarioEspecialID: horarioID,
                etiqueta: timbre.etiqueta.trimmingCharacters(in: .whitespacesAndNewlines),
                hora: timbre.hora,
                duracionSeg: timbre.duracionSeg ?? 5
            )
            try await nuevo.create(on: db)
            for dia in Set(timbre.dias) {
                try await TimbreEspecialDia(timbreEspecialID: try nuevo.requireID(), dia: dia).create(on: db)
            }
        }
    }

    private func recargar(_ id: UUID, on db: any Database) async throws -> HorarioEspecialDTO {
        // Sin trailing closure: dentro de una condición `guard` el compilador
        // la confundiría con el bloque `else`.
        guard let horario = try await HorarioEspecial.query(on: db)
            .filter(\.$id == id)
            .with(\.$timbres, { $0.with(\.$dias) })
            .first()
        else {
            throw Abort(.internalServerError, reason: "El horario recién guardado no aparece")
        }
        return try dto(de: horario, hoy: FormatoTiempo.hoyISO())
    }

    private func dto(de horario: HorarioEspecial, hoy: String) throws -> HorarioEspecialDTO {
        HorarioEspecialDTO(
            id: try horario.requireID(),
            nombre: horario.nombre,
            fechaInicio: horario.fechaInicio,
            fechaFin: horario.fechaFin,
            activo: horario.activo,
            vigente: horario.vigente(en: hoy),
            timbres: try horario.timbres
                .sorted { $0.hora < $1.hora }
                .map { timbre in
                    TimbreEspecialDTO(
                        id: try timbre.requireID(),
                        etiqueta: timbre.etiqueta,
                        hora: timbre.hora,
                        duracionSeg: timbre.duracionSeg,
                        dias: timbre.dias.map(\.dia).ordenados()
                    )
                }
        )
    }

    private func validar(_ datos: GuardarHorarioEspecialRequest) throws {
        guard !datos.nombre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "El nombre del horario especial es obligatorio")
        }
        try FormatoTiempo.validarFecha(datos.fechaInicio)
        try FormatoTiempo.validarFecha(datos.fechaFin)
        guard datos.fechaInicio <= datos.fechaFin else {
            throw Abort(.badRequest, reason: "La fecha de inicio no puede ser posterior a la de fin")
        }
        for timbre in datos.timbres {
            guard !timbre.etiqueta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw Abort(.badRequest, reason: "Todos los timbres necesitan etiqueta")
            }
            try FormatoTiempo.validarHora(timbre.hora)
            guard !timbre.dias.isEmpty else {
                throw Abort(.badRequest, reason: "Cada timbre debe sonar al menos un día")
            }
        }
    }
}
