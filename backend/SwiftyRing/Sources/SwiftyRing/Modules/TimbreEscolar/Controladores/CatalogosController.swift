//
//  CatalogosController.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  Catálogos de materias y salones. Cualquier usuario autenticado los lee
//  (los formularios los necesitan); solo el administrador los modifica.
//

import Vapor
import Fluent

struct MateriaDTO: Content {
    let id: UUID
    let nombre: String
    let activo: Bool

    init(_ materia: Materia) throws {
        self.id = try materia.requireID()
        self.nombre = materia.nombre
        self.activo = materia.activo
    }
}

struct SalonDTO: Content {
    let id: UUID
    let nombre: String
    let bloque: String?
    let piso: Int?
    let capacidad: Int?
    let activo: Bool

    init(_ salon: Salon) throws {
        self.id = try salon.requireID()
        self.nombre = salon.nombre
        self.bloque = salon.bloque
        self.piso = salon.piso
        self.capacidad = salon.capacidad
        self.activo = salon.activo
    }
}

struct CrearMateriaRequest: Content {
    let nombre: String
}

struct CrearSalonRequest: Content {
    let nombre: String
    let bloque: String?
    let piso: Int?
    let capacidad: Int?
}

struct CatalogosController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let api = routes.grouped("api").grouped(SwiftyRingAuthMiddleware())

        let materias = api.grouped("materias")
        materias.get(use: listarMaterias)
        materias.post(use: crearMateria)
        materias.delete(":id", use: retirarMateria)

        let salones = api.grouped("salones")
        salones.get(use: listarSalones)
        salones.post(use: crearSalon)
        salones.delete(":id", use: retirarSalon)
    }

    // MARK: Materias

    func listarMaterias(req: Request) async throws -> [MateriaDTO] {
        try await Materia.query(on: req.db)
            .filter(\.$activo == true)
            .sort(\.$nombre)
            .all()
            .map(MateriaDTO.init)
    }

    func crearMateria(req: Request) async throws -> MateriaDTO {
        try req.exigirRol(.admin)
        let datos = try req.content.decode(CrearMateriaRequest.self)
        let nombre = datos.nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nombre.isEmpty else {
            throw Abort(.badRequest, reason: "El nombre de la materia es obligatorio")
        }
        let materia = Materia(nombre: nombre)
        try await materia.create(on: req.db)
        return try MateriaDTO(materia)
    }

    /// Retira la materia del catálogo sin borrarla: los bloques históricos que
    /// la referencian siguen siendo válidos.
    func retirarMateria(req: Request) async throws -> HTTPStatus {
        try req.exigirRol(.admin)
        guard let materia = try await Materia.find(req.parameters.get("id"), on: req.db) else {
            throw Abort(.notFound, reason: "La materia no existe")
        }
        materia.activo = false
        try await materia.save(on: req.db)
        return .noContent
    }

    // MARK: Salones

    func listarSalones(req: Request) async throws -> [SalonDTO] {
        try await Salon.query(on: req.db)
            .filter(\.$activo == true)
            .sort(\.$nombre)
            .all()
            .map(SalonDTO.init)
    }

    func crearSalon(req: Request) async throws -> SalonDTO {
        try req.exigirRol(.admin)
        let datos = try req.content.decode(CrearSalonRequest.self)
        let nombre = datos.nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nombre.isEmpty else {
            throw Abort(.badRequest, reason: "El nombre del salón es obligatorio")
        }
        let salon = Salon(nombre: nombre, bloque: datos.bloque, piso: datos.piso, capacidad: datos.capacidad)
        try await salon.create(on: req.db)
        return try SalonDTO(salon)
    }

    func retirarSalon(req: Request) async throws -> HTTPStatus {
        try req.exigirRol(.admin)
        guard let salon = try await Salon.find(req.parameters.get("id"), on: req.db) else {
            throw Abort(.notFound, reason: "El salón no existe")
        }
        salon.activo = false
        try await salon.save(on: req.db)
        return .noContent
    }
}
