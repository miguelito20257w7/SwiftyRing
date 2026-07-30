//
//  JWKSController.swift
//  SwiftyRing · Core/Auth
//
//  Publica la llave pública con la que cualquier consumidor externo verifica
//  los tokens que emite este backend (RF-46).
//

import Vapor
import JWT
import Foundation

/// Expone `/.well-known/jwks.json`.
///
/// Es el único endpoint **público sin autenticación** aparte del login, y es
/// correcto que lo sea: una llave pública está pensada para repartirse. Lo que
/// nunca sale de aquí es la privada (RNF-13).
///
/// El backend de Control Baños SS consulta esta ruta, cachea el resultado y
/// verifica con él cada token que recibe. Al ser un endpoint estándar, su
/// cliente de JWT sabe consumirlo sin inventar un formato propio.
struct JWKSController: RouteCollection {

    func boot(routes: any RoutesBuilder) throws {
        routes.get(".well-known", "jwks.json", use: jwks)

        // Alternativa en PEM, más cómoda si el otro equipo prefiere pegar la
        // llave en un archivo de configuración en vez de consultar la URL.
        routes.get(".well-known", "jwt-public-key.pem", use: pem)
    }

    /// RF-46 · Llave pública en formato JWKS.
    func jwks(req: Request) async throws -> Response {
        let llave = try Insecure.RSA.PublicKey(pem: JWTConfig.llavePublicaPEM())

        // Un JWK de RSA se describe con dos números: el módulo (n) y el
        // exponente público (e), ambos en base64url.
        let (modulo, exponente) = try llave.getKeyPrimitives()

        let jwk = JWK.rsa(
            .rs256,
            identifier: JWTIdentidad.kid,
            modulus: modulo.base64URLEncoded(),
            exponent: exponente.base64URLEncoded()
        )

        // `JWKS` no es `Content`, así que se serializa a mano.
        let json = try JSONEncoder().encode(JWKS(keys: [jwk]))

        let respuesta = Response(status: .ok, body: .init(data: json))
        respuesta.headers.contentType = .json
        // La llave solo cambia al rotarla; una hora de caché evita que cada
        // request del otro backend pase por aquí.
        respuesta.headers.replaceOrAdd(name: .cacheControl, value: "public, max-age=3600")
        return respuesta
    }

    /// La misma llave, en PEM.
    func pem(req: Request) async throws -> Response {
        let respuesta = Response(
            status: .ok,
            body: .init(string: try JWTConfig.llavePublicaPEM())
        )
        respuesta.headers.contentType = .plainText
        respuesta.headers.replaceOrAdd(name: .cacheControl, value: "public, max-age=3600")
        return respuesta
    }
}

private extension Data {
    /// base64url sin relleno, que es como el estándar JWK exige los números.
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
