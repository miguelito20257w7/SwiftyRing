//
//  Autorizacion.swift
//  SwiftyRing · Core/Auth
//
//  Autorización por rol encima del middleware de autenticación: el middleware
//  responde "¿quién eres?"; esto responde "¿puedes hacer esto?".
//

import Vapor

extension Request {
    /// El payload del token, garantizando que el rol está en la lista.
    ///
    /// 401 si no hay sesión; 403 si la hay pero el rol no alcanza (RF-05,
    /// RF-06: los permisos se deciden por rol en cada endpoint).
    @discardableResult
    func exigirRol(_ roles: RolUsuario...) throws -> SwiftyRingPayload {
        let payload = try requireSwiftyRingPayload()
        guard roles.contains(payload.rol) else {
            throw Abort(.forbidden, reason: "Tu rol no tiene permiso para esta operación")
        }
        return payload
    }
}
