//
//  AuthController.swift
//  SwiftyRing
//
//  Created by Miguel Angel Salazar Garcia on 7/21/26.
//

import Vapor
import Fluent
import JWT

struct AuthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        // Todo lo de autenticacion cuelga de /api/auth
        let auth = routes.grouped("api", "auth")

        // Publica: aca es donde se pide el token.
        auth.post("login", use: login)

        // Privadas: hay que mandar `Authorization: Bearer <token>`.
        let protegidas = auth.grouped(SwiftyRingAuthMiddleware())
        protegidas.get("me", use: me)
    }

    /// RF-01 · Inicio de sesion. Valida credenciales contra PostgreSQL (bcrypt)
    /// y devuelve un JWT firmado + los datos publicos del usuario.
    func login(req: Request) async throws -> LoginResponse {
        try LoginRequest.validate(content: req)
        let loginRequest = try req.content.decode(LoginRequest.self)

        // Los correos se guardan y se buscan siempre en minusculas, para que
        // "Andrea@..." y "andrea@..." sean el mismo usuario.
        let email = loginRequest.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Un solo mensaje para "no existe", "clave mala" y "suspendido": si
        // fueran distintos, cualquiera podria ir probando correos hasta ver
        // cual responde diferente y asi averiguar quien tiene cuenta.
        let credencialesInvalidas = Abort(.unauthorized, reason: "Correo o contraseña incorrectos")

        guard let usuario = try await Usuario.query(on: req.db)
            .filter(\.$email == email)
            .first()
        else {
            throw credencialesInvalidas
        }

        let claveCorrecta = try await req.password.async.verify(
            loginRequest.password,
            created: usuario.passwordHash
        )
        guard claveCorrecta else {
            throw credencialesInvalidas
        }

        // RF-03: una cuenta suspendida sigue existiendo pero no puede entrar.
        guard usuario.activo else {
            throw credencialesInvalidas
        }

        // RNF-08: la duracion del token se configura por variable de entorno.
        let horas = Environment.get("JWT_EXPIRATION_HOURS").flatMap(Double.init) ?? 24

        // RF-45: el token lleva emisor, audiencias, nombre y correo, para que
        // un consumidor externo (Control Baños SS) sepa quien actua sin tocar
        // la tabla `usuarios`.
        let payload = SwiftyRingPayload.paraUsuario(
            id: try usuario.requireID(),
            nombre: usuario.nombre,
            email: usuario.email,
            rol: usuario.rol,
            duracionEnHoras: horas
        )

        return LoginResponse(
            token: try await req.jwt.sign(payload),
            usuario: try UserResponse(usuario: usuario)
        )
    }

    /// Devuelve el usuario dueño del token. Sirve para que la app revalide la
    /// sesion al abrir (token guardado en secure storage) y para comprobar que
    /// la cadena token → middleware → base de datos funciona.
    func me(req: Request) async throws -> UserResponse {
        let payload = try req.requireSwiftyRingPayload()

        guard let id = payload.usuarioID,
              let usuario = try await Usuario.find(id, on: req.db),
              usuario.activo
        else {
            // El token es valido pero el usuario ya no existe o lo suspendieron.
            throw Abort(.unauthorized, reason: "Sesión no válida")
        }

        return try UserResponse(usuario: usuario)
    }
}
