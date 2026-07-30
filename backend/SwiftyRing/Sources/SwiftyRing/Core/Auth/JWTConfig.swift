//
//  JWTConfig.swift
//  SwiftyRing · Core/Auth
//
//  Configuración de las llaves con las que se firman y verifican los JWT.
//

import Vapor
import JWT

/// Identidad del emisor y de las audiencias que reconoce el sistema.
///
/// Estos valores viajan dentro de cada token (`iss` y `aud`) y **son parte del
/// contrato con Control Baños SS**: si cambian, su backend deja de aceptar los
/// tokens. Cualquier modificación requiere acuerdo escrito entre los equipos
/// (Contrato de integración, sección 6).
enum JWTIdentidad {
    /// Quién emite los tokens. Solo el Sistema de Timbre Escolar.
    static let emisor = "timbre-escolar"

    /// Para qué módulos vale un token emitido aquí.
    static let audiencias = ["timbre", "banos"]

    /// Identificador de la llave, para poder rotarla sin invalidar todo de
    /// golpe: el JWKS puede publicar dos llaves a la vez durante la rotación.
    static let kid = JWKIdentifier(string: "timbre-2026")
}

/// Carga el par de llaves RSA y las registra en la aplicación.
///
/// **Por qué RS256 y no HMAC** (RF-44): con HMAC la llave que firma y la que
/// verifica son la misma. Entregársela a Control Baños para que valide tokens
/// les permitiría también *emitirlos*, incluido uno con rol `admin` sobre este
/// backend. Con RS256 la privada no sale de aquí (RNF-13) y solo se publica la
/// pública, que sirve para verificar pero no para firmar.
enum JWTConfig {
    /// Registra la llave privada (firma + verificación local).
    ///
    /// Falla al arrancar si no encuentra la llave: es preferible que el
    /// servidor no levante a que levante emitiendo tokens que nadie puede
    /// verificar, o —peor— con una llave de ejemplo.
    static func configurar(_ app: Application) async throws {
        let pem = try leerPEM(
            variable: "JWT_PRIVATE_KEY_PATH",
            porDefecto: "keys/jwt_private.pem",
            descripcion: "llave privada de firma RS256"
        )

        let llave = try Insecure.RSA.PrivateKey(pem: pem)
        await app.jwt.keys.add(rsa: llave, digestAlgorithm: .sha256, kid: JWTIdentidad.kid)

        app.logger.info("JWT: firmando con RS256, kid \(JWTIdentidad.kid.string)")
    }

    /// La llave pública en formato PEM, tal como se publica y se comparte.
    static func llavePublicaPEM() throws -> String {
        try leerPEM(
            variable: "JWT_PUBLIC_KEY_PATH",
            porDefecto: "keys/jwt_public.pem",
            descripcion: "llave pública de verificación RS256"
        )
    }

    private static func leerPEM(
        variable: String,
        porDefecto: String,
        descripcion: String
    ) throws -> String {
        let ruta = Environment.get(variable) ?? porDefecto

        guard let contenido = try? String(contentsOfFile: ruta, encoding: .utf8) else {
            throw Abort(
                .internalServerError,
                reason: """
                No se encontró la \(descripcion) en «\(ruta)». \
                Generá el par con:
                  openssl genrsa -out keys/jwt_private.pem 2048
                  openssl rsa -in keys/jwt_private.pem -pubout -out keys/jwt_public.pem
                o apuntá \(variable) a su ubicación real.
                """
            )
        }

        return contenido
    }
}
