//
//  DispositivoController.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  La API que consume el módulo físico ESP32. Cuatro conversaciones:
//
//    1. `GET  /api/dispositivo/horario`      — baja el horario semanal completo
//       y la calibración sísmica, para guardarlos en su flash (RF-28).
//    2. `GET  /api/dispositivo/comandos`     — pregunta cada ~2 s si la app
//       ordenó timbrar (RNF-04); esta consulta hace de latido "en línea".
//    3. `POST /api/dispositivo/activaciones` — reporta que sonó (automático o
//       botón físico) para la bitácora (RF-17) y las notificaciones (RF-36).
//    4. `POST /api/dispositivo/sismos`       — reporta un evento sísmico
//       confirmado (RF-22).
//
//  El módulo no es un usuario: se autentica con una llave fija en la cabecera
//  `X-Device-Key` (variable DEVICE_API_KEY). Si la llave no está configurada
//  en el servidor, los endpoints responden 503: mejor un error claro que un
//  módulo aceptado sin autenticar.
//

import Vapor
import Fluent

/// Autenticación del módulo físico por llave compartida.
struct DispositivoAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let esperada = Environment.get("DEVICE_API_KEY"), !esperada.isEmpty else {
            throw Abort(.serviceUnavailable, reason: "DEVICE_API_KEY no está configurada en el servidor")
        }
        guard let recibida = request.headers.first(name: "X-Device-Key"), recibida == esperada else {
            throw Abort(.unauthorized, reason: "Llave de dispositivo inválida")
        }
        return try await next.respond(to: request)
    }
}

/// Un timbre como lo necesita el módulo: sin más metadatos que los que usa
/// para decidir cuándo sonar.
struct TimbreDispositivoDTO: Content {
    let id: UUID
    let etiqueta: String
    let hora: String
    let duracionSeg: Int
    let dias: [DiaSemana]
}

struct HorarioEspecialDispositivoDTO: Content {
    let nombre: String
    let fechaInicio: String
    let fechaFin: String
    let timbres: [TimbreDispositivoDTO]
}

/// Todo lo que el módulo guarda en flash para operar solo (RF-28, RF-31):
/// el horario habitual completo y, si existe, el especial con su rango. Van
/// los dos para que el módulo decida bien aunque pase días sin conexión y el
/// especial venza estando offline (RF-12).
struct HorarioDispositivoResponse: Content {
    let fechaServidor: String
    let horaServidor: String
    let umbralSismicoG: Double
    let sismoDuracionMinMs: Int
    let habitual: [TimbreDispositivoDTO]
    let especial: HorarioEspecialDispositivoDTO?
}

struct ComandosResponse: Content {
    /// ¿Hay orden de timbre manual pendiente? (RF-14, RNF-04)
    let timbrar: Bool
    let duracionSeg: Int?
}

struct ReporteActivacionRequest: Content {
    /// `automatico` o `manual_fisico`; los otros orígenes no salen del módulo.
    let tipo: String
    /// Timbre programado que la originó, si fue automática.
    let horarioTimbreId: UUID?
    let duracionSeg: Int?
    /// Hace cuántos segundos ocurrió. El módulo lo calcula con su propio
    /// reloj, así los reportes encolados offline llegan con su momento real
    /// aunque el módulo no sepa la fecha absoluta con precisión.
    let ocurridoHaceSeg: Int?
}

struct ReporteSismoRequest: Content {
    let intensidadG: Double
    let duracionMs: Int
    let timbreActivado: Bool?
    let ocurridoHaceSeg: Int?
}

struct DispositivoController: RouteCollection {

    /// Un reporte más viejo que esto no dispara notificaciones de próxima
    /// clase: avisarle a un docente de la clase que siguió a un timbre de hace
    /// horas (sincronización tardía) sería ruido, no información (RF-36).
    private static let ventanaNotificacionesSeg = 120

    /// Hasta cuándo sigue teniendo sentido avisar de un sismo (15 minutos).
    private static let ventanaAvisoSismoSeg = 900

    func boot(routes: any RoutesBuilder) throws {
        let dispositivo = routes.grouped("api", "dispositivo")
            .grouped(DispositivoAuthMiddleware())

        dispositivo.get("horario", use: horario)
        dispositivo.get("comandos", use: comandos)
        dispositivo.post("activaciones", use: reportarActivacion)
        dispositivo.post("sismos", use: reportarSismo)
    }

    /// RF-28: el paquete completo que el módulo guarda en LittleFS. También
    /// deja constancia de la sincronización (`ultima_sync` en configuración).
    func horario(req: Request) async throws -> HorarioDispositivoResponse {
        await EstadoModulo.compartido.registrarContacto()

        let config = try await ConfiguracionSistema.actual(on: req.db)
        config.ultimaSync = Date()
        try await config.save(on: req.db)

        let habituales = try await HorarioTimbre.query(on: req.db)
            .filter(\.$activo == true)
            .with(\.$dias)
            .sort(\.$hora)
            .all()
            .map { timbre in
                TimbreDispositivoDTO(
                    id: try timbre.requireID(),
                    etiqueta: timbre.etiqueta,
                    hora: timbre.hora,
                    duracionSeg: timbre.duracionSeg,
                    dias: timbre.dias.map(\.dia).ordenados()
                )
            }

        // El especial vigente hoy o el próximo a entrar en vigencia: si el
        // módulo pierde conexión hoy, mañana puede empezar una semana de
        // exámenes y debe tenerla ya en la flash.
        let hoy = FormatoTiempo.hoyISO()
        let especial = try await HorarioEspecial.query(on: req.db)
            .filter(\.$activo == true)
            .filter(\.$fechaFin >= hoy)
            .sort(\.$fechaInicio)
            .with(\.$timbres, { $0.with(\.$dias) })
            .first()

        let especialDTO = try especial.map { horario in
            HorarioEspecialDispositivoDTO(
                nombre: horario.nombre,
                fechaInicio: horario.fechaInicio,
                fechaFin: horario.fechaFin,
                timbres: try horario.timbres
                    .sorted { $0.hora < $1.hora }
                    .map { timbre in
                        TimbreDispositivoDTO(
                            id: try timbre.requireID(),
                            etiqueta: timbre.etiqueta,
                            hora: timbre.hora,
                            duracionSeg: timbre.duracionSeg,
                            dias: timbre.dias.map(\.dia).ordenados()
                        )
                    }
            )
        }

        return HorarioDispositivoResponse(
            fechaServidor: hoy,
            horaServidor: FormatoTiempo.horaActual(),
            umbralSismicoG: config.umbralSismicoG,
            sismoDuracionMinMs: config.sismoDuracionMinMs,
            habitual: habituales,
            especial: especialDTO
        )
    }

    /// El latido del módulo: registra el contacto y entrega la orden de
    /// timbre pendiente, si la app dejó una (RNF-04: el módulo consulta cada
    /// ~2 s, así la orden llega dentro del plazo).
    func comandos(req: Request) async throws -> ComandosResponse {
        await EstadoModulo.compartido.registrarContacto()
        let duracion = await EstadoModulo.compartido.retirarOrden()
        return ComandosResponse(timbrar: duracion != nil, duracionSeg: duracion)
    }

    /// RF-17: bitácora de lo que sonó en el colegio, venga del horario
    /// automático (RF-31) o del botón físico (RF-15).
    func reportarActivacion(req: Request) async throws -> HTTPStatus {
        await EstadoModulo.compartido.registrarContacto()
        let datos = try req.content.decode(ReporteActivacionRequest.self)

        guard let tipo = TipoActivacion(rawValue: datos.tipo),
              tipo == .automatico || tipo == .manualFisico
        else {
            throw Abort(.badRequest, reason: "Tipo inválido: el módulo solo reporta automatico o manual_fisico")
        }

        let haceSeg = max(0, datos.ocurridoHaceSeg ?? 0)
        let activacion = ActivacionTimbre(
            tipo: tipo,
            ocurridoAt: Date().addingTimeInterval(-Double(haceSeg)),
            horarioTimbreID: datos.horarioTimbreId,
            duracionSeg: datos.duracionSeg
        )
        try await activacion.create(on: req.db)

        if haceSeg <= Self.ventanaNotificacionesSeg {
            _ = try await NotificadorProximaClase.generar(
                activacionID: activacion.requireID(),
                on: req
            )
        }

        return .created
    }

    /// RF-22: el módulo detectó y confirmó un sismo. Queda el evento (RF-23),
    /// su activación de timbre y las notificaciones de clase si es reciente.
    func reportarSismo(req: Request) async throws -> HTTPStatus {
        await EstadoModulo.compartido.registrarContacto()
        let datos = try req.content.decode(ReporteSismoRequest.self)

        guard datos.intensidadG > 0, datos.duracionMs > 0 else {
            throw Abort(.badRequest, reason: "Intensidad y duración deben ser positivas")
        }

        let haceSeg = max(0, datos.ocurridoHaceSeg ?? 0)
        let ocurridoAt = Date().addingTimeInterval(-Double(haceSeg))
        let timbreActivado = datos.timbreActivado ?? true

        let evento = EventoSismico(
            intensidadG: datos.intensidadG,
            duracionMs: datos.duracionMs,
            ocurridoAt: ocurridoAt,
            timbreActivado: timbreActivado
        )

        try await req.db.transaction { db in
            if timbreActivado {
                let activacion = ActivacionTimbre(tipo: .sismico, ocurridoAt: ocurridoAt, duracionSeg: 30)
                try await activacion.create(on: db)
                evento.activacionID = try activacion.requireID()
            }
            try await evento.create(on: db)
        }

        // RF-20: el administrador se entera aunque el sismo no haya activado el
        // timbre. La ventana es más ancha que la de las clases porque tres
        // minutos de retraso no vuelven irrelevante una emergencia; pero
        // tampoco es infinita, para que un módulo que estuvo días sin conexión
        // no despierte a nadie con una ráfaga de alarmas viejas.
        if haceSeg <= Self.ventanaAvisoSismoSeg {
            await NotificadorSismo.avisar(evento, on: req)
        }

        if timbreActivado, haceSeg <= Self.ventanaNotificacionesSeg,
           let activacionID = evento.activacionID {
            _ = try await NotificadorProximaClase.generar(activacionID: activacionID, on: req)
        }

        return .created
    }
}
