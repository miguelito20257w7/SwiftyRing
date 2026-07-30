import Fluent
import Vapor

struct SeedAdminUsuario: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let existingAdmin = try await Usuario.query(on: database)
            .filter(\.$rol == .admin)
            .first()

        guard existingAdmin == nil else { return }

        // El correo se guarda normalizado (sin espacios y en minusculas) porque
        // asi lo busca el login.
        let email = (Environment.get("ADMIN_EMAIL") ?? "admin@swiftyring.dev")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let plainPassword = Environment.get("ADMIN_PASSWORD") ?? "changeme123"

        let admin = Usuario(
            nombre: "Administrador Principal",
            email: email,
            passwordHash: try Bcrypt.hash(plainPassword),
            rol: .admin
        )

        try await admin.create(on: database)
    }

    func revert(on database: any Database) async throws {
        try await Usuario.query(on: database)
            .filter(\.$rol == .admin)
            .delete()
    }
}
