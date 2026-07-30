//
//  SwiftyRingPayload.swift
//  SwiftyRing · Core/Auth
//
//  Contenido de los tokens que emite este backend. Aquí se agregan las reglas
//  de validación (por ejemplo: rechazar un token cuya audiencia no incluya al
//  módulo que lo está usando).
//

import JWT
import Vapor
import Foundation

/// Claims del JWT emitido por el Sistema de Timbre Escolar.
///
/// **Este payload es contrato público** (RF-45): el backend de Control Baños SS
/// lo decodifica con la llave pública. Quitar un claim o cambiarle el nombre
/// rompe su módulo. Agregar uno nuevo es seguro; quitarlo no.
///
/// `nombre` y `email` viajan dentro del token a propósito: permiten que un
/// consumidor externo sepa quién actúa sin consultar la tabla `usuarios`, que
/// es de este sistema y sobre la que solo tiene permiso de lectura.
struct SwiftyRingPayload: JWTPayload, Authenticatable {

    /// El id del usuario, como texto.
    var subject: SubjectClaim

    /// Cuándo vence el token.
    var expirationClaim: ExpirationClaim

    /// Cuándo se emitió.
    var issuedAt: IssuedAtClaim

    /// Quién lo emitió. Siempre `timbre-escolar`.
    var issuer: IssuerClaim

    /// Para qué módulos vale.
    var audience: AudienceClaim

    /// Rol de la cuenta. Va en el token para no consultar la base de datos en
    /// cada request solo para saber qué puede hacer quien lo manda.
    var rol: RolUsuario

    var nombre: String
    var email: String

    // El JSON del token usa los nombres del estándar JWT (RFC 7519). Sin esto
    // saldría con las claves "subject"/"expirationClaim" y ninguna herramienta
    // externa (jwt.io, la app, el backend de Control Baños) sabría leerlo.
    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case expirationClaim = "exp"
        case issuedAt = "iat"
        case issuer = "iss"
        case audience = "aud"
        case rol
        case nombre
        case email
    }

    /// El id del usuario dueño del token, ya convertido a UUID.
    var usuarioID: UUID? {
        UUID(uuidString: self.subject.value)
    }

    func verify(using algorithm: some JWTAlgorithm) throws {
        try self.expirationClaim.verifyNotExpired()

        // Un token firmado por otro emisor no vale aquí, aunque la firma
        // llegara a cuadrar durante una rotación de llaves.
        guard self.issuer.value == JWTIdentidad.emisor else {
            throw JWTError.claimVerificationFailure(
                failedClaim: self.issuer,
                reason: "El token no fue emitido por \(JWTIdentidad.emisor)"
            )
        }

        // La audiencia se comprueba contra el módulo que atiende el request.
        // Aquí solo se exige que incluya a "timbre"; el backend de Control
        // Baños hace lo propio con "banos".
        try self.audience.verifyIntendedAudience(includes: "timbre")
    }

    /// Construye el payload de una sesión recién iniciada.
    static func paraUsuario(
        id: UUID,
        nombre: String,
        email: String,
        rol: RolUsuario,
        duracionEnHoras horas: Double
    ) -> SwiftyRingPayload {
        SwiftyRingPayload(
            subject: SubjectClaim(value: id.uuidString),
            expirationClaim: ExpirationClaim(value: Date().addingTimeInterval(horas * 3600)),
            issuedAt: IssuedAtClaim(value: Date()),
            issuer: IssuerClaim(value: JWTIdentidad.emisor),
            audience: AudienceClaim(value: JWTIdentidad.audiencias),
            rol: rol,
            nombre: nombre,
            email: email
        )
    }
}
