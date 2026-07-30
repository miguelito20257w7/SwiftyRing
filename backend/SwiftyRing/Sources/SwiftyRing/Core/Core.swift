//
//  Core.swift
//  SwiftyRing · Core
//
//  Punto de entrada del núcleo: lo que este backend ofrece a **toda** la
//  aplicación institucional, no solo al módulo de timbres.
//

import Vapor
import Fluent

/// El núcleo: identidad, emisión y verificación de tokens.
///
/// Es la parte que el backend de Control Baños SS consume (sin poder
/// modificarla) y la que no debe depender de ningún módulo. La regla es la
/// misma que en la app Flutter:
///
/// * un módulo **puede** usar `Core`;
/// * `Core` **no puede** usar un módulo.
///
/// Si algún día `Core` necesitara algo de `Modules/TimbreEscolar`, eso es señal
/// de que la pieza estaba mal ubicada: o sube al núcleo, o el módulo la resuelve
/// por su cuenta.
enum Core {

    /// Migraciones de las tablas de identidad, en orden de aplicación.
    static var migraciones: [any AsyncMigration] {
        [
            CreateUsuario(),
            SeedAdminUsuario(),
        ]
    }

    /// Rutas del núcleo: autenticación, gestión de cuentas y publicación de la
    /// llave pública.
    static func registrarRutas(_ app: Application) throws {
        try app.register(collection: AuthController())
        try app.register(collection: UsuariosController())
        try app.register(collection: JWKSController())
    }
}
