import NIOSSL
import Fluent
import FluentPostgresDriver
import Vapor
import JWT

/// Arranque de la aplicación.
///
/// Es la **raíz de composición** del backend, igual que `main.dart` en la app
/// Flutter: el único sitio que conoce a la vez el núcleo y todos los módulos.
func configure(_ app: Application) async throws {
    // Permite que la app Flutter (otro origen/puerto) le pegue a esta API desde
    // el navegador. En producción, cambiar `.all` por el dominio real.
    app.middleware.use(
        CORSMiddleware(configuration: .init(
            allowedOrigin: .all,
            allowedMethods: [.GET, .POST, .PUT, .DELETE, .PATCH, .OPTIONS],
            allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith]
        )),
        at: .beginning
    )

    app.databases.use(DatabaseConfigurationFactory.postgres(configuration: .init(
        hostname: Environment.get("DATABASE_HOST") ?? "localhost",
        port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber,
        username: Environment.get("DATABASE_USERNAME") ?? "vapor_username",
        password: Environment.get("DATABASE_PASSWORD") ?? "vapor_password",
        database: Environment.get("DATABASE_NAME") ?? "vapor_database",
        tls: .prefer(try .init(configuration: .clientDefault)))
    ), as: .psql)

    // Las fechas viajan como texto ISO-8601 en el JSON. Sin esto, Foundation
    // las serializa como segundos desde 2001 y la app tendría que adivinarlo.
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    ContentConfiguration.global.use(encoder: encoder, for: .json)
    ContentConfiguration.global.use(decoder: decoder, for: .json)

    // RF-44: firma RS256. Antes era HMAC-SHA512 con una llave compartida; el
    // porqué del cambio está en `Core/Auth/JWTConfig.swift`.
    try await JWTConfig.configurar(app)

    app.passwords.use(.bcrypt)

    // ---- Migraciones ----
    // Del núcleo: la identidad, que es lo que este backend ofrece como servidor
    // de autenticación al resto de la aplicación institucional.
    for migracion in Core.migraciones {
        app.migrations.add(migracion)
    }
    // De cada módulo. Añadir un módulo es añadir una línea aquí.
    for migracion in TimbreEscolar.migraciones {
        app.migrations.add(migracion)
    }

    try routes(app)
}
