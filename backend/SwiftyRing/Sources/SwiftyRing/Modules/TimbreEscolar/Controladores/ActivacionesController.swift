//
//  ActivacionesController.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  El timbre manual desde la app (RF-14, RF-16, RF-17), la bitácora de
//  activaciones y sismos (F-08) y la generación de notificaciones de próxima
//  clase (RF-36..RF-38).
//
//  Sobre el envío real: al activarse el timbre se calcula qué profesor tiene
//  clase a continuación y se registra su notificación en PostgreSQL. El tramo
//  FCM (empujar ese registro al teléfono) es infraestructura externa y queda
//  detrás de `enviada = false` hasta que el proyecto tenga las llaves FCM.
//

import Vapor
import Fluent

struct ActivacionDTO: Content {
    let id: UUID
    let tipo: TipoActivacion
    let ocurridoAt: Date
    let usuarioNombre: String?
    let duracionSeg: Int?
    /// Cuántos profesores tenían clase a continuación (solo al activar).
    let notificacionesGeneradas: Int?
}

struct SismoDTO: Content {
    let id: UUID
    let intensidadG: Double
    let duracionMs: Int
    let ocurridoAt: Date
    let timbreActivado: Bool
    let notificacionEnviada: Bool
}

struct NotificacionDTO: Content {
    let id: UUID
    let profesorNombre: String
    let mensaje: String
    let enviada: Bool
    let ocurridoAt: Date
}

struct RegistrarSismoRequest: Content {
    let intensidadG: Double
    let duracionMs: Int
}

struct RegistrarDispositivoRequest: Content {
    let plataforma: Plataforma
    let fcmToken: String
    let nombreDispositivo: String?
}

/// Un dispositivo vinculado, como lo pinta "Tus dispositivos vinculados" en
/// Configuración (frame 1:214). Lleva el token FCM porque solo se responde al
/// dueño, y es como la app reconoce cuál de la lista es *este* teléfono.
struct DispositivoDTO: Content {
    let id: UUID
    let plataforma: Plataforma
    let nombreDispositivo: String?
    let fcmToken: String
    let registradoAt: Date?
    let ultimoUsoAt: Date?
}

struct ActivacionesController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let api = routes.grouped("api").grouped(SwiftyRingAuthMiddleware())

        // RF-14: el botón de timbre manual de la pantalla principal.
        api.post("timbre", "manual", use: timbreManual)

        api.get("activaciones", use: listarActivaciones)
        api.get("sismos", use: listarSismos)
        api.post("sismos", use: registrarSismo)
        api.get("notificaciones", use: listarNotificaciones)
        api.post("dispositivos", use: registrarDispositivo)
        api.get("dispositivos", use: listarDispositivos)
        api.delete("dispositivos", ":dispositivoId", use: desvincularDispositivo)
    }

    /// RF-16: ejecuta el timbre de inmediato, sin mirar el horario. Queda en
    /// la bitácora con usuario y origen `manual_app` (RF-17), deja la orden
    /// lista para que el módulo la recoja (RNF-04) y dispara las
    /// notificaciones de próxima clase (P-03).
    func timbreManual(req: Request) async throws -> ActivacionDTO {
        let payload = try req.exigirRol(.admin, .operador)
        guard let usuarioID = payload.usuarioID else {
            throw Abort(.unauthorized, reason: "Sesión no válida")
        }

        let activacion = ActivacionTimbre(
            tipo: .manualApp,
            origenUsuarioID: usuarioID,
            duracionSeg: 5
        )
        try await activacion.create(on: req.db)

        // El módulo consulta sus comandos cada ~2 s; con esto el toque llega
        // dentro del plazo de RNF-04 sin que el servidor tenga que buscarlo.
        await EstadoModulo.compartido.ordenarTimbre(duracionSeg: activacion.duracionSeg ?? 5)

        let notificadas = try await NotificadorProximaClase.generar(
            activacionID: activacion.requireID(),
            on: req
        )

        return ActivacionDTO(
            id: try activacion.requireID(),
            tipo: .manualApp,
            ocurridoAt: activacion.ocurridoAt,
            usuarioNombre: payload.nombre,
            duracionSeg: activacion.duracionSeg,
            notificacionesGeneradas: notificadas
        )
    }

    /// F-08: bitácora de activaciones, filtrable por rango de fechas
    /// (`?desde=yyyy-MM-dd&hasta=yyyy-MM-dd`).
    func listarActivaciones(req: Request) async throws -> [ActivacionDTO] {
        try req.exigirRol(.admin, .operador)

        var consulta = ActivacionTimbre.query(on: req.db)
        if let desde = try fechaLimite(req, "desde", finDeDia: false) {
            consulta = consulta.filter(\.$ocurridoAt >= desde)
        }
        if let hasta = try fechaLimite(req, "hasta", finDeDia: true) {
            consulta = consulta.filter(\.$ocurridoAt <= hasta)
        }

        let activaciones = try await consulta
            .sort(\.$ocurridoAt, .descending)
            .limit(200)
            .all()

        // Los nombres de quienes activaron, en una sola consulta.
        let usuarioIDs = activaciones.compactMap(\.origenUsuarioID)
        let usuarios = try await Usuario.query(on: req.db)
            .filter(\.$id ~~ usuarioIDs)
            .all()
        let nombrePorID = Dictionary(uniqueKeysWithValues: try usuarios.map { (try $0.requireID(), $0.nombre) })

        return try activaciones.map { activacion in
            ActivacionDTO(
                id: try activacion.requireID(),
                tipo: activacion.tipo,
                ocurridoAt: activacion.ocurridoAt,
                usuarioNombre: activacion.origenUsuarioID.flatMap { nombrePorID[$0] },
                duracionSeg: activacion.duracionSeg,
                notificacionesGeneradas: nil
            )
        }
    }

    /// RF-23: historial de eventos sísmicos.
    func listarSismos(req: Request) async throws -> [SismoDTO] {
        try req.exigirRol(.admin, .operador)

        var consulta = EventoSismico.query(on: req.db)
        if let desde = try fechaLimite(req, "desde", finDeDia: false) {
            consulta = consulta.filter(\.$ocurridoAt >= desde)
        }
        if let hasta = try fechaLimite(req, "hasta", finDeDia: true) {
            consulta = consulta.filter(\.$ocurridoAt <= hasta)
        }

        return try await consulta
            .sort(\.$ocurridoAt, .descending)
            .limit(200)
            .all()
            .map { evento in
                SismoDTO(
                    id: try evento.requireID(),
                    intensidadG: evento.intensidadG,
                    duracionMs: evento.duracionMs,
                    ocurridoAt: evento.ocurridoAt,
                    timbreActivado: evento.timbreActivado,
                    notificacionEnviada: evento.notificacionEnviada
                )
            }
    }

    /// RF-22: registra un evento sísmico confirmado. En producción lo reporta
    /// el módulo ESP32; desde la app sirve para simulacros del administrador.
    /// Crea el evento, su activación de tipo `sismico` y las notificaciones.
    func registrarSismo(req: Request) async throws -> SismoDTO {
        try req.exigirRol(.admin)
        let datos = try req.content.decode(RegistrarSismoRequest.self)

        guard datos.intensidadG > 0, datos.duracionMs > 0 else {
            throw Abort(.badRequest, reason: "Intensidad y duración deben ser positivas")
        }

        let activacion = ActivacionTimbre(tipo: .sismico, duracionSeg: 30)
        let evento = EventoSismico(intensidadG: datos.intensidadG, duracionMs: datos.duracionMs)

        try await req.db.transaction { db in
            try await activacion.create(on: db)
            evento.activacionID = try activacion.requireID()
            try await evento.create(on: db)
        }

        // RF-20/RF-21: el administrador se entera del evento por push.
        await NotificadorSismo.avisar(evento, on: req)
        _ = try await NotificadorProximaClase.generar(activacionID: activacion.requireID(), on: req)

        return SismoDTO(
            id: try evento.requireID(),
            intensidadG: evento.intensidadG,
            duracionMs: evento.duracionMs,
            ocurridoAt: evento.ocurridoAt,
            timbreActivado: evento.timbreActivado,
            notificacionEnviada: evento.notificacionEnviada
        )
    }

    /// F-08: notificaciones registradas. El administrador las ve todas; el
    /// profesor solo las suyas.
    func listarNotificaciones(req: Request) async throws -> [NotificacionDTO] {
        let payload = try req.requireSwiftyRingPayload()

        var consulta = NotificacionProfesor.query(on: req.db)
        if payload.rol == .profesor {
            guard let profesorID = payload.usuarioID else {
                throw Abort(.unauthorized, reason: "Sesión no válida")
            }
            consulta = consulta.filter(\.$profesorID == profesorID)
        }

        let notificaciones = try await consulta.limit(200).all()

        let profesorIDs = notificaciones.map(\.profesorID)
        let usuarios = try await Usuario.query(on: req.db).filter(\.$id ~~ profesorIDs).all()
        let nombrePorID = Dictionary(uniqueKeysWithValues: try usuarios.map { (try $0.requireID(), $0.nombre) })

        let activacionIDs = notificaciones.map(\.activacionID)
        let activaciones = try await ActivacionTimbre.query(on: req.db).filter(\.$id ~~ activacionIDs).all()
        let fechaPorID = Dictionary(uniqueKeysWithValues: try activaciones.map { (try $0.requireID(), $0.ocurridoAt) })

        return try notificaciones
            .map { notificacion in
                NotificacionDTO(
                    id: try notificacion.requireID(),
                    profesorNombre: nombrePorID[notificacion.profesorID] ?? "—",
                    mensaje: notificacion.mensaje,
                    enviada: notificacion.enviada,
                    ocurridoAt: fechaPorID[notificacion.activacionID] ?? Date()
                )
            }
            .sorted { $0.ocurridoAt > $1.ocurridoAt }
    }

    /// Registra (o refresca) el token FCM del dispositivo que llama. Si el
    /// token ya existía —reinstalación— se actualiza el dueño y el último uso.
    func registrarDispositivo(req: Request) async throws -> HTTPStatus {
        let payload = try req.requireSwiftyRingPayload()
        guard let usuarioID = payload.usuarioID else {
            throw Abort(.unauthorized, reason: "Sesión no válida")
        }
        let datos = try req.content.decode(RegistrarDispositivoRequest.self)
        guard !datos.fcmToken.isEmpty else {
            throw Abort(.badRequest, reason: "El token FCM es obligatorio")
        }

        if let existente = try await Dispositivo.query(on: req.db)
            .filter(\.$fcmToken == datos.fcmToken)
            .first() {
            existente.usuarioID = usuarioID
            existente.plataforma = datos.plataforma
            existente.nombreDispositivo = datos.nombreDispositivo ?? existente.nombreDispositivo
            existente.activo = true
            existente.ultimoUsoAt = Date()
            try await existente.save(on: req.db)
        } else {
            let dispositivo = Dispositivo(
                usuarioID: usuarioID,
                plataforma: datos.plataforma,
                fcmToken: datos.fcmToken,
                nombreDispositivo: datos.nombreDispositivo
            )
            dispositivo.ultimoUsoAt = Date()
            try await dispositivo.create(on: req.db)
        }
        return .noContent
    }

    /// "Tus dispositivos vinculados" (F-07): cada usuario ve **solo los
    /// suyos**, del más reciente al más viejo. No hay variante de
    /// administrador: los tokens FCM son direcciones de entrega personales y
    /// nadie necesita las ajenas.
    func listarDispositivos(req: Request) async throws -> [DispositivoDTO] {
        let payload = try req.requireSwiftyRingPayload()
        guard let usuarioID = payload.usuarioID else {
            throw Abort(.unauthorized, reason: "Sesión no válida")
        }

        return try await Dispositivo.query(on: req.db)
            .filter(\.$usuarioID == usuarioID)
            .filter(\.$activo == true)
            .sort(\.$ultimoUsoAt, .descending)
            .all()
            .map { dispositivo in
                DispositivoDTO(
                    id: try dispositivo.requireID(),
                    plataforma: dispositivo.plataforma,
                    nombreDispositivo: dispositivo.nombreDispositivo,
                    fcmToken: dispositivo.fcmToken,
                    registradoAt: dispositivo.registradoAt,
                    ultimoUsoAt: dispositivo.ultimoUsoAt
                )
            }
    }

    /// El "Cerrar sesión" de un dispositivo vinculado: se borra el registro y
    /// ese teléfono deja de recibir avisos. Solo el dueño puede; si el
    /// dispositivo vuelve a abrir la app con sesión, se re-registra solo.
    func desvincularDispositivo(req: Request) async throws -> HTTPStatus {
        let payload = try req.requireSwiftyRingPayload()
        guard let usuarioID = payload.usuarioID else {
            throw Abort(.unauthorized, reason: "Sesión no válida")
        }
        guard let dispositivoID: UUID = req.parameters.get("dispositivoId"),
              let dispositivo = try await Dispositivo.find(dispositivoID, on: req.db),
              dispositivo.usuarioID == usuarioID
        else {
            // El mismo 404 exista o sea de otro: no se confirma la existencia
            // de dispositivos ajenos.
            throw Abort(.notFound, reason: "El dispositivo no existe")
        }

        try await dispositivo.delete(on: req.db)
        return .noContent
    }

    /// Convierte `?desde=` / `?hasta=` en límites de día en hora de Colombia.
    private func fechaLimite(_ req: Request, _ nombre: String, finDeDia: Bool) throws -> Date? {
        guard let texto: String = req.query[nombre] else { return nil }
        try FormatoTiempo.validarFecha(texto)

        let formato = DateFormatter()
        formato.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formato.timeZone = FormatoTiempo.zonaColombia
        return formato.date(from: "\(texto) \(finDeDia ? "23:59:59" : "00:00:00")")
    }
}
