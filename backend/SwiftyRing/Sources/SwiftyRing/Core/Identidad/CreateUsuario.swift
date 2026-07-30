import Fluent

struct CreateUsuario: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let rolUsuario = try await database.enum("rol_usuario")
            .case("admin")
            .case("operador")
            .case("profesor")
            .create()

        try await database.schema(Usuario.schema)
            .id()
            .field("nombre", .string, .required)
            .field("email", .string, .required)
            .field("password_hash", .string, .required)
            .field("rol", rolUsuario, .required)
            .field("activo", .bool, .required)
            .field("creado_at", .datetime, .required)
            .field("actualizado_at", .datetime, .required)
            .unique(on: "email")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Usuario.schema).delete()
        try await database.enum("rol_usuario").delete()
    }
}
