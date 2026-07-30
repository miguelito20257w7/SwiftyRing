//
//  UsuariosController.swift
//  SwiftyRing · Core/Identidad
//
//  Gestión de cuentas (RF-03, RF-06) para la pantalla de Configuración. Vive
//  en Core porque las cuentas son identidad de toda la aplicación
//  institucional, no del módulo de timbres.
//
//  Los docentes NO se crean aquí: nacen con su perfil en Gestión de Docentes
//  (módulo TimbreEscolar), que garantiza cuenta y perfil en una transacción.
//

import Vapor
import Fluent

struct UsuarioAdminDTO: Content {
    let id: UUID
    let nombre: String
    let email: String
    let rol: RolUsuario
    let activo: Bool
    /// RF-02: la cuenta principal no se puede suspender ni eliminar; la app
    /// esconde esas acciones y el backend las rechaza.
    let esPrincipal: Bool
}

struct CrearUsuarioRequest: Content, Validatable {
    let nombre: String
    let email: String
    let password: String
    let rol: RolUsuario

    static func validations(_ validations: inout Validations) {
        validations.add("nombre", as: String.self, is: !.empty)
        validations.add("email", as: String.self, is: .email)
        validations.add("password", as: String.self, is: .count(8...))
    }
}

struct EditarUsuarioRequest: Content {
    let nombre: String?
    let activo: Bool?
    let password: String?
}

struct UsuariosController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let usuarios = routes.grouped("api")
            .grouped(SwiftyRingAuthMiddleware())
            .grouped("usuarios")

        usuarios.get(use: listar)
        usuarios.post(use: crear)
        usuarios.put(":id", use: editar)
        usuarios.delete(":id", use: eliminar)
    }

    /// El correo de la cuenta principal (Doña Andrea), sembrada en la
    /// inicialización (RF-02).
    private var emailPrincipal: String {
        Environment.get("ADMIN_EMAIL")?.lowercased() ?? "andrea@santasofia.edu.co"
    }

    func listar(req: Request) async throws -> [UsuarioAdminDTO] {
        try req.exigirRol(.admin)
        return try await Usuario.query(on: req.db)
            .sort(\.$nombre)
            .all()
            .map { usuario in
                UsuarioAdminDTO(
                    id: try usuario.requireID(),
                    nombre: usuario.nombre,
                    email: usuario.email,
                    rol: usuario.rol,
                    activo: usuario.activo,
                    esPrincipal: usuario.email == emailPrincipal
                )
            }
    }

    /// RF-03: crear usuarios secundarios (admin u operador).
    func crear(req: Request) async throws -> UsuarioAdminDTO {
        try req.exigirRol(.admin)
        try CrearUsuarioRequest.validate(content: req)
        let datos = try req.content.decode(CrearUsuarioRequest.self)

        guard datos.rol != .profesor else {
            throw Abort(.badRequest, reason: "Los docentes se crean desde Gestión de Docentes, con su jornada y materias")
        }

        let email = datos.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if try await Usuario.query(on: req.db).filter(\.$email == email).first() != nil {
            throw Abort(.conflict, reason: "Ya existe una cuenta con ese correo")
        }

        let usuario = Usuario(
            nombre: datos.nombre.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email,
            passwordHash: try await req.password.async.hash(datos.password),
            rol: datos.rol
        )
        try await usuario.create(on: req.db)

        return UsuarioAdminDTO(
            id: try usuario.requireID(),
            nombre: usuario.nombre,
            email: usuario.email,
            rol: usuario.rol,
            activo: usuario.activo,
            esPrincipal: false
        )
    }

    /// RF-03: editar nombre, suspender/reactivar o cambiar contraseña.
    func editar(req: Request) async throws -> UsuarioAdminDTO {
        try req.exigirRol(.admin)
        let datos = try req.content.decode(EditarUsuarioRequest.self)

        guard let usuario = try await Usuario.find(req.parameters.get("id"), on: req.db) else {
            throw Abort(.notFound, reason: "El usuario no existe")
        }

        // RF-02: a la cuenta principal no se le puede quitar el acceso.
        if usuario.email == emailPrincipal, datos.activo == false {
            throw Abort(.forbidden, reason: "La cuenta del administrador principal no se puede suspender")
        }

        if let nombre = datos.nombre?.trimmingCharacters(in: .whitespacesAndNewlines), !nombre.isEmpty {
            usuario.nombre = nombre
        }
        if let activo = datos.activo {
            usuario.activo = activo
        }
        if let password = datos.password {
            guard password.count >= 8 else {
                throw Abort(.badRequest, reason: "La contraseña debe tener al menos 8 caracteres")
            }
            usuario.passwordHash = try await req.password.async.hash(password)
        }
        try await usuario.save(on: req.db)

        return UsuarioAdminDTO(
            id: try usuario.requireID(),
            nombre: usuario.nombre,
            email: usuario.email,
            rol: usuario.rol,
            activo: usuario.activo,
            esPrincipal: usuario.email == emailPrincipal
        )
    }

    /// RF-03: eliminar. La cuenta principal es intocable (RF-02).
    func eliminar(req: Request) async throws -> HTTPStatus {
        let payload = try req.exigirRol(.admin)

        guard let usuario = try await Usuario.find(req.parameters.get("id"), on: req.db) else {
            throw Abort(.notFound, reason: "El usuario no existe")
        }
        guard usuario.email != emailPrincipal else {
            throw Abort(.forbidden, reason: "La cuenta del administrador principal no se puede eliminar (RF-02)")
        }
        // Eliminarse a sí mismo dejaría la sesión actual colgando de nada.
        if payload.usuarioID == (try? usuario.requireID()) {
            throw Abort(.forbidden, reason: "No puedes eliminar tu propia cuenta con la sesión abierta")
        }

        try await usuario.delete(on: req.db)
        return .noContent
    }
}
