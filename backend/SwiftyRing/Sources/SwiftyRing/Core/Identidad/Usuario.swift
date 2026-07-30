import Fluent
import Foundation

final class Usuario: Model, @unchecked Sendable {
    static let schema = "usuarios"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "nombre")
    var nombre: String

    @Field(key: "email")
    var email: String

    @Field(key: "password_hash")
    var passwordHash: String

    @Enum(key: "rol")
    var rol: RolUsuario

    @Field(key: "activo")
    var activo: Bool

    @Timestamp(key: "creado_at", on: .create)
    var creadoAt: Date?

    @Timestamp(key: "actualizado_at", on: .update)
    var actualizadoAt: Date?

    init() { }

    init(
        id: UUID? = nil,
        nombre: String,
        email: String,
        passwordHash: String,
        rol: RolUsuario,
        activo: Bool = true
    ) {
        self.id = id
        self.nombre = nombre
        self.email = email
        self.passwordHash = passwordHash
        self.rol = rol
        self.activo = activo
    }
}
