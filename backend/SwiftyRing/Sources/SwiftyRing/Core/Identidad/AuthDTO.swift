//
//  AuthDTO.swift
//  SwiftyRing
//
//  Created by Miguel Angel Salazar Garcia on 7/21/26.
//

import Vapor
import Fluent // por `requireID()` del modelo Usuario

struct LoginRequest: Content { // vamos a poner aca en nuestra peticion que contenido tendra nuestro json y que contenido devolvera el json de nuestro backend
    let email: String
    let password: String
}

// Reglas minimas de la peticion: si el JSON llega vacio o el correo no parece
// correo, cortamos antes de tocar la base de datos.
extension LoginRequest: Validatable {
    static func validations(_ validations: inout Validations) {
        validations.add("email", as: String.self, is: .email)
        validations.add("password", as: String.self, is: !.empty)
    }
}

struct LoginResponse: Content {
    let token: String
    let usuario: UserResponse
}

struct UserResponse: Content {
    let id: UUID
    let nombre: String
    let email: String
    let rol: RolUsuario
}

extension UserResponse {
    /// Arma la respuesta publica de un usuario. Nunca expone `passwordHash`.
    init(usuario: Usuario) throws {
        self.init(
            id: try usuario.requireID(),
            nombre: usuario.nombre,
            email: usuario.email,
            rol: usuario.rol
        )
    }
}
