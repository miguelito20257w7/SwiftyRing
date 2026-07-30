//
//  SwiftyRingAuthMiddleware.swift
//  SwiftyRing
//
//  Middleware que protege las rutas privadas: lee el header
//  `Authorization: Bearer <token>`, verifica la firma y la expiracion, y deja
//  el payload disponible en `req.auth` para el resto del request.
//
//  Todas las rutas que vengan despues del login (horarios, timbres, usuarios...)
//  van a colgar de este middleware.
//

import Vapor
import JWT

struct SwiftyRingAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        // Si no hay token, esta vencido o la firma no cuadra, esto lanza 401.
        let payload = try await request.jwt.verify(as: SwiftyRingPayload.self)
        request.auth.login(payload)
        return try await next.respond(to: request)
    }
}

extension Request {
    /// El payload del token del usuario autenticado. Lanza 401 si la ruta no
    /// pasó por `SwiftyRingAuthMiddleware`.
    func requireSwiftyRingPayload() throws -> SwiftyRingPayload {
        try self.auth.require(SwiftyRingPayload.self)
    }
}
