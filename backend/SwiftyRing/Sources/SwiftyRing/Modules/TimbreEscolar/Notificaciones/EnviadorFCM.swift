//
//  EnviadorFCM.swift
//  SwiftyRing · Modules/TimbreEscolar/Notificaciones
//
//  Entrega de notificaciones push por Firebase Cloud Messaging (RF-20, RF-21,
//  RF-37). FCM se usa **solo como canal de entrega**: ni la identidad ni los
//  datos del sistema pasan por Firebase, tal como exige el alcance del
//  proyecto.
//
//  Por qué no hay una librería de Firebase aquí: la API HTTP v1 de FCM son dos
//  peticiones HTTP —una para conseguir un token de acceso y otra para enviar— y
//  el backend ya tiene todo lo necesario para hacerlas (vapor/jwt para firmar y
//  el cliente HTTP de Vapor). Añadir un SDK sería más superficie que mantener a
//  cambio de nada.
//
//  Regla que gobierna todo este archivo: **el timbre nunca falla porque falle
//  Google.** Si no hay credencial, si la red se cae o si FCM responde con
//  error, la activación ya quedó registrada y la notificación simplemente
//  permanece con `enviada = false`, lista para auditarse en el historial.
//

import Vapor
import JWT
import Foundation

// MARK: - Credencial

/// Los tres datos que hacen falta del archivo JSON de la cuenta de servicio
/// que genera la consola de Firebase.
struct CuentaServicioFCM: Sendable, Decodable {
    let projectID: String
    let clientEmail: String
    let privateKeyPEM: String

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case clientEmail = "client_email"
        case privateKeyPEM = "private_key"
    }

    /// Lee la credencial del archivo apuntado por `FCM_CREDENTIALS_PATH`.
    ///
    /// Devuelve `nil` —y no lanza— cuando no está configurada: un colegio que
    /// todavía no tiene proyecto de Firebase debe poder operar el timbre igual.
    /// Solo lanza si el archivo existe pero está corrupto, porque eso sí es un
    /// error que hay que corregir y no un estado válido del sistema.
    static func cargar(logger: Logger) throws -> CuentaServicioFCM? {
        guard let ruta = Environment.get("FCM_CREDENTIALS_PATH"), !ruta.isEmpty else {
            logger.notice("FCM: sin FCM_CREDENTIALS_PATH; las notificaciones se registran pero no se envían")
            return nil
        }
        guard let datos = FileManager.default.contents(atPath: ruta) else {
            logger.warning("FCM: no se encontró la credencial en «\(ruta)»; las notificaciones no se enviarán")
            return nil
        }
        let cuenta = try JSONDecoder().decode(CuentaServicioFCM.self, from: datos)
        logger.info("FCM: credencial cargada para el proyecto \(cuenta.projectID)")
        return cuenta
    }
}

// MARK: - Enviador

/// Envía notificaciones push y guarda el token de acceso de Google mientras
/// siga vigente.
///
/// Es un `actor` porque el token de acceso es estado compartido: al sonar el
/// timbre pueden salir decenas de envíos a la vez y sin esta protección todos
/// pedirían su propio token a Google simultáneamente.
actor EnviadorFCM {

    static let compartido = EnviadorFCM()

    private var cuenta: CuentaServicioFCM?

    /// Token de acceso vigente y cuándo deja de serlo. Google los emite con una
    /// hora de vida; se renueva un minuto antes para no usar uno recién vencido.
    private var tokenAcceso: String?
    private var tokenVenceEn: Date?

    /// Resultado de un envío, para que quien llama sepa qué marcar en la base.
    struct Resultado: Sendable {
        /// Tokens que FCM aceptó.
        var entregados: [String] = []
        /// Tokens que FCM rechazó por no existir ya (app desinstalada, token
        /// rotado). Hay que desactivar esos dispositivos.
        var muertos: [String] = []

        var huboEntrega: Bool { !entregados.isEmpty }
    }

    /// Carga la credencial al arrancar el servidor.
    func configurar(logger: Logger) {
        cuenta = try? CuentaServicioFCM.cargar(logger: logger)
    }

    var estaConfigurado: Bool { cuenta != nil }

    /// Envía el mismo mensaje a varios dispositivos, en paralelo.
    ///
    /// El paralelismo es un requerimiento, no una optimización: RNF-05 exige
    /// que el aviso llegue a todos los profesores en menos de 5 segundos, y en
    /// serie una planta docente completa no cabría en ese plazo.
    func enviar(
        a tokens: [String],
        titulo: String,
        cuerpo: String,
        datos: [String: String] = [:],
        client: any Client,
        logger: Logger
    ) async -> Resultado {
        guard let cuenta, !tokens.isEmpty else { return Resultado() }

        guard let acceso = await tokenDeAcceso(cuenta: cuenta, client: client, logger: logger) else {
            logger.warning("FCM: no se pudo obtener el token de acceso; no se envía nada")
            return Resultado()
        }

        return await withTaskGroup(of: (String, EstadoEnvio).self) { grupo in
            for token in tokens {
                grupo.addTask {
                    let estado = await Self.enviarUno(
                        token: token,
                        titulo: titulo,
                        cuerpo: cuerpo,
                        datos: datos,
                        projectID: cuenta.projectID,
                        acceso: acceso,
                        client: client,
                        logger: logger
                    )
                    return (token, estado)
                }
            }

            var resultado = Resultado()
            for await (token, estado) in grupo {
                switch estado {
                case .entregado: resultado.entregados.append(token)
                case .tokenMuerto: resultado.muertos.append(token)
                case .fallo: break  // reintentar no es responsabilidad de este envío
                }
            }
            return resultado
        }
    }

    // MARK: Token de acceso (OAuth2 con cuenta de servicio)

    /// Un token de acceso vigente, pidiéndoselo a Google solo si hace falta.
    private func tokenDeAcceso(
        cuenta: CuentaServicioFCM,
        client: any Client,
        logger: Logger
    ) async -> String? {
        if let tokenAcceso, let tokenVenceEn, tokenVenceEn > Date() {
            return tokenAcceso
        }

        do {
            // Google pide un JWT firmado con la llave privada de la cuenta de
            // servicio y lo cambia por un token de acceso de corta vida.
            let llaves = JWTKeyCollection()
            let privada = try Insecure.RSA.PrivateKey(pem: cuenta.privateKeyPEM)
            await llaves.add(rsa: privada, digestAlgorithm: .sha256)

            let ahora = Date()
            let afirmacion = try await llaves.sign(
                PayloadCuentaServicio(
                    iss: IssuerClaim(value: cuenta.clientEmail),
                    scope: "https://www.googleapis.com/auth/firebase.messaging",
                    aud: AudienceClaim(value: "https://oauth2.googleapis.com/token"),
                    exp: ExpirationClaim(value: ahora.addingTimeInterval(3600)),
                    iat: IssuedAtClaim(value: ahora)
                )
            )

            let respuesta = try await client.post("https://oauth2.googleapis.com/token") { peticion in
                try peticion.content.encode(
                    SolicitudToken(assertion: afirmacion),
                    as: .urlEncodedForm
                )
            }

            guard respuesta.status == .ok else {
                logger.warning("FCM: Google rechazó la credencial (\(respuesta.status.code))")
                return nil
            }

            let token = try respuesta.content.decode(RespuestaToken.self)
            tokenAcceso = token.accessToken
            // Un minuto de margen: un token que vence en vuelo es un envío perdido.
            tokenVenceEn = Date().addingTimeInterval(Double(token.expiresIn) - 60)
            return token.accessToken
        } catch {
            logger.report(error: error)
            return nil
        }
    }

    // MARK: Envío individual

    private enum EstadoEnvio {
        case entregado
        /// El dispositivo ya no existe: hay que dejar de intentarlo.
        case tokenMuerto
        case fallo
    }

    private static func enviarUno(
        token: String,
        titulo: String,
        cuerpo: String,
        datos: [String: String],
        projectID: String,
        acceso: String,
        client: any Client,
        logger: Logger
    ) async -> EstadoEnvio {
        do {
            let respuesta = try await client.post(
                URI(string: "https://fcm.googleapis.com/v1/projects/\(projectID)/messages:send"),
                headers: ["Authorization": "Bearer \(acceso)"]
            ) { peticion in
                try peticion.content.encode(
                    SobreFCM(message: .init(token: token, titulo: titulo, cuerpo: cuerpo, datos: datos))
                )
            }

            switch respuesta.status.code {
            case 200:
                return .entregado
            case 400, 403, 404:
                // 404 = el token ya no está registrado (app desinstalada o
                // token rotado); 400 = token mal formado. En ambos casos
                // reintentar es inútil.
                logger.info("FCM: token descartado (\(respuesta.status.code))")
                return .tokenMuerto
            default:
                logger.warning("FCM: envío fallido (\(respuesta.status.code))")
                return .fallo
            }
        } catch {
            logger.warning("FCM: error de red al enviar: \(String(reflecting: error))")
            return .fallo
        }
    }
}

// MARK: - Formas de los mensajes

/// El JWT que se le presenta a Google para pedir un token de acceso.
private struct PayloadCuentaServicio: JWTPayload {
    var iss: IssuerClaim
    var scope: String
    var aud: AudienceClaim
    var exp: ExpirationClaim
    var iat: IssuedAtClaim

    /// Este payload solo se firma; el que lo verifica es Google.
    func verify(using algorithm: some JWTAlgorithm) throws {}
}

private struct SolicitudToken: Content {
    let grantType = "urn:ietf:params:oauth:grant-type:jwt-bearer"
    let assertion: String

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case assertion
    }
}

private struct RespuestaToken: Content {
    let accessToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

/// El cuerpo que espera FCM HTTP v1.
private struct SobreFCM: Content {
    let message: Mensaje

    struct Mensaje: Content {
        let token: String
        let notification: Notificacion
        let data: [String: String]
        let android: Android
        let apns: APNS

        init(token: String, titulo: String, cuerpo: String, datos: [String: String]) {
            self.token = token
            self.notification = Notificacion(title: titulo, body: cuerpo)
            self.data = datos
            // Prioridad alta en los dos sistemas: un cambio de clase o una
            // alerta sísmica no pueden esperar a que el teléfono despierte.
            self.android = Android(priority: "high")
            self.apns = APNS(headers: ["apns-priority": "10"])
        }
    }

    struct Notificacion: Content {
        let title: String
        let body: String
    }

    struct Android: Content {
        let priority: String
    }

    struct APNS: Content {
        let headers: [String: String]
    }
}
