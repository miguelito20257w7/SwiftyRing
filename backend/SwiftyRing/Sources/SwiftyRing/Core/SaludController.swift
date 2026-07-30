//
//  SaludController.swift
//  SwiftyRing · Core
//
//  Una sonda pública para que la app pueda comprobar que la dirección que le
//  escribieron apunta de verdad a un servidor de SwiftyRing.
//
//  No basta con que el host responda 200: en una red escolar, un nombre mal
//  escrito puede caer en el router, en una impresora o en el portal cautivo del
//  proveedor, y todos ellos contestan alegremente. Por eso la respuesta se
//  identifica: si no viene `servicio: "swiftyring"`, la app sabe que está
//  hablando con otra cosa y lo dice en vez de fallar más adelante con un error
//  incomprensible.
//

import Vapor

struct SaludResponse: Content {
    /// La firma que busca la app. No cambiar sin actualizarla también allá.
    let servicio = "swiftyring"
    /// Quién emite los tokens; sirve para distinguir instalaciones.
    let emisor = JWTIdentidad.emisor
    let version = "1.0"
}

struct SaludController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        // Pública a propósito: se consulta antes de tener sesión, justo para
        // saber a dónde pedirla.
        routes.get("api", "salud", use: salud)
    }

    func salud(req: Request) async throws -> SaludResponse {
        SaludResponse()
    }
}
