//
//  ProfesoresController.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  Gestión de docentes (RF-32, RF-33) y la lista de solo lectura que consume
//  el módulo Control Baños SS (RF-47).
//
//  Un "docente" son dos filas que nacen y viven juntas: la cuenta en
//  `usuarios` (Core, rol profesor) y el perfil en `profesores` (este módulo).
//  Por eso las escrituras van en transacción: no puede quedar cuenta sin
//  perfil ni perfil sin cuenta.
//

import Vapor
import Fluent

struct ProfesorDTO: Content {
    let id: UUID
    let nombre: String
    let email: String
    let activo: Bool
    let jornada: Jornada
    let directorDeGrupo: String?
    let materias: [MateriaDTO]
}

struct CrearProfesorRequest: Content, Validatable {
    let nombre: String
    let email: String
    let password: String
    let jornada: Jornada
    let directorDeGrupo: String?
    let materiaIds: [UUID]

    static func validations(_ validations: inout Validations) {
        validations.add("nombre", as: String.self, is: !.empty)
        validations.add("email", as: String.self, is: .email)
        validations.add("password", as: String.self, is: .count(8...))
    }
}

struct EditarProfesorRequest: Content {
    let nombre: String
    let jornada: Jornada
    let directorDeGrupo: String?
    let materiaIds: [UUID]
}

struct ProfesoresController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let profesores = routes.grouped("api")
            .grouped(SwiftyRingAuthMiddleware())
            .grouped("profesores")

        profesores.get(use: listar)
        profesores.post(use: crear)
        profesores.put(":id", use: editar)
        profesores.delete(":id", use: suspender)
    }

    /// RF-47: lista de docentes activos, solo administrador. Es el único
    /// endpoint de este sistema que consume el módulo externo, y es de
    /// lectura (RF-48).
    func listar(req: Request) async throws -> [ProfesorDTO] {
        try req.exigirRol(.admin)

        let perfiles = try await Profesor.query(on: req.db).all()
        let usuarios = try await Usuario.query(on: req.db)
            .filter(\.$rol == .profesor)
            .filter(\.$activo == true)
            .sort(\.$nombre)
            .all()

        let perfilPorID = Dictionary(uniqueKeysWithValues: try perfiles.map { (try $0.requireID(), $0) })

        // Las materias de todos los profesores en dos consultas, no una por fila.
        let asignaciones = try await ProfesorMateria.query(on: req.db).all()
        let materias = try await Materia.query(on: req.db).all()
        let materiaPorID = Dictionary(uniqueKeysWithValues: try materias.map { (try $0.requireID(), $0) })

        return try usuarios.compactMap { usuario in
            let id = try usuario.requireID()
            // Cuenta con rol profesor pero sin perfil: dato a medio migrar; no
            // se lista hasta que el perfil exista.
            guard let perfil = perfilPorID[id] else { return nil }

            let materiasDelProfesor = try asignaciones
                .filter { $0.profesorID == id }
                .compactMap { materiaPorID[$0.materiaID] }
                .map(MateriaDTO.init)
                .sorted { $0.nombre < $1.nombre }

            return ProfesorDTO(
                id: id,
                nombre: usuario.nombre,
                email: usuario.email,
                activo: usuario.activo,
                jornada: perfil.jornada,
                directorDeGrupo: perfil.directorDeGrupo,
                materias: materiasDelProfesor
            )
        }
    }

    /// RF-33: alta de docente. Crea cuenta + perfil + materias en transacción.
    func crear(req: Request) async throws -> ProfesorDTO {
        try req.exigirRol(.admin)
        try CrearProfesorRequest.validate(content: req)
        let datos = try req.content.decode(CrearProfesorRequest.self)

        let email = datos.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let nombre = datos.nombre.trimmingCharacters(in: .whitespacesAndNewlines)

        if try await Usuario.query(on: req.db).filter(\.$email == email).first() != nil {
            throw Abort(.conflict, reason: "Ya existe una cuenta con ese correo")
        }

        let passwordHash = try await req.password.async.hash(datos.password)

        let usuario = Usuario(nombre: nombre, email: email, passwordHash: passwordHash, rol: .profesor)

        try await req.db.transaction { db in
            try await usuario.create(on: db)
            let usuarioID = try usuario.requireID()

            let perfil = Profesor(
                usuarioID: usuarioID,
                jornada: datos.jornada,
                directorDeGrupo: datos.directorDeGrupo?.vacioComoNil()
            )
            try await perfil.create(on: db)

            for materiaID in Set(datos.materiaIds) {
                try await ProfesorMateria(profesorID: usuarioID, materiaID: materiaID).create(on: db)
            }
        }

        return try await dto(de: usuario, on: req.db)
    }

    /// RF-33: edición de docente. El correo no se cambia por aquí: es la
    /// credencial de inicio de sesión y cambiarla es una operación de cuentas
    /// (Configuración), no de perfil docente.
    func editar(req: Request) async throws -> ProfesorDTO {
        try req.exigirRol(.admin)
        let datos = try req.content.decode(EditarProfesorRequest.self)

        guard let usuario = try await Usuario.find(req.parameters.get("id"), on: req.db),
              usuario.rol == .profesor,
              let perfil = try await Profesor.find(usuario.requireID(), on: req.db)
        else {
            throw Abort(.notFound, reason: "El docente no existe")
        }

        let nombre = datos.nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nombre.isEmpty else {
            throw Abort(.badRequest, reason: "El nombre es obligatorio")
        }

        try await req.db.transaction { db in
            usuario.nombre = nombre
            try await usuario.save(on: db)

            perfil.jornada = datos.jornada
            perfil.directorDeGrupo = datos.directorDeGrupo?.vacioComoNil()
            try await perfil.save(on: db)

            // Las materias se reemplazan completas: la app manda el estado
            // final del formulario, no diferencias.
            let usuarioID = try usuario.requireID()
            try await ProfesorMateria.query(on: db)
                .filter(\.$profesorID == usuarioID)
                .delete()
            for materiaID in Set(datos.materiaIds) {
                try await ProfesorMateria(profesorID: usuarioID, materiaID: materiaID).create(on: db)
            }
        }

        return try await dto(de: usuario, on: req.db)
    }

    /// RF-03: suspender, no borrar. El perfil y sus bloques quedan intactos
    /// para el historial; la cuenta simplemente ya no puede entrar ni aparece
    /// en las listas.
    func suspender(req: Request) async throws -> HTTPStatus {
        try req.exigirRol(.admin)

        guard let usuario = try await Usuario.find(req.parameters.get("id"), on: req.db),
              usuario.rol == .profesor
        else {
            throw Abort(.notFound, reason: "El docente no existe")
        }

        usuario.activo = false
        try await usuario.save(on: req.db)
        return .noContent
    }

    // MARK: - Apoyo

    private func dto(de usuario: Usuario, on db: any Database) async throws -> ProfesorDTO {
        let id = try usuario.requireID()
        guard let perfil = try await Profesor.find(id, on: db) else {
            throw Abort(.internalServerError, reason: "Docente sin perfil")
        }

        let materiaIDs = try await ProfesorMateria.query(on: db)
            .filter(\.$profesorID == id)
            .all()
            .map(\.materiaID)

        let materias = try await Materia.query(on: db)
            .filter(\.$id ~~ materiaIDs)
            .sort(\.$nombre)
            .all()
            .map(MateriaDTO.init)

        return ProfesorDTO(
            id: id,
            nombre: usuario.nombre,
            email: usuario.email,
            activo: usuario.activo,
            jornada: perfil.jornada,
            directorDeGrupo: perfil.directorDeGrupo,
            materias: materias
        )
    }
}

extension String {
    /// `""` y `"   "` se tratan como "sin valor". Evita que un campo opcional
    /// vacío del formulario acabe guardado como texto en blanco.
    func vacioComoNil() -> String? {
        let limpio = trimmingCharacters(in: .whitespacesAndNewlines)
        return limpio.isEmpty ? nil : limpio
    }
}
