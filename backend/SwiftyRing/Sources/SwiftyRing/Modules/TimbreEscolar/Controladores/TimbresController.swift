//
//  TimbresController.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  Timbres del horario habitual (RF-07..RF-09) y la consulta "¿qué suena
//  hoy?" que alimenta la pantalla principal (F-02): lista del día, próximo
//  toque y si rige el horario habitual o uno especial.
//

import Vapor
import Fluent

struct TimbreDTO: Content {
    let id: UUID
    let etiqueta: String
    let hora: String
    let duracionSeg: Int
    let activo: Bool
    let dias: [DiaSemana]
}

struct GuardarTimbreRequest: Content {
    let etiqueta: String
    let hora: String
    let duracionSeg: Int?
    let activo: Bool?
    let dias: [DiaSemana]
}

/// Un toque del día, venga del horario habitual o de uno especial.
struct TimbreDelDiaDTO: Content {
    let id: UUID
    let etiqueta: String
    let hora: String
    let duracionSeg: Int
}

struct TimbresHoyResponse: Content {
    /// `"habitual"` o `"especial"` (RF-10: el especial suspende al habitual).
    let fuente: String
    /// Nombre del horario especial vigente, si lo hay.
    let nombreEspecial: String?
    /// Día de hoy; `nil` los domingos (no hay timbres programables).
    let dia: DiaSemana?
    /// Hora del servidor en Colombia, `"HH:mm"`; referencia para "próximo".
    let horaServidor: String
    let timbres: [TimbreDelDiaDTO]
    let proximo: TimbreDelDiaDTO?
}

struct TimbresController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let timbres = routes.grouped("api")
            .grouped(SwiftyRingAuthMiddleware())
            .grouped("timbres")

        timbres.get(use: listar)
        timbres.get("hoy", use: hoy)
        timbres.post(use: crear)
        timbres.put(":id", use: editar)
        timbres.delete(":id", use: eliminar)
    }

    /// Todos los timbres del horario habitual con sus días. Lo ven todos los
    /// roles: el operador consulta horarios aunque no los edite (RF-05).
    func listar(req: Request) async throws -> [TimbreDTO] {
        let timbres = try await HorarioTimbre.query(on: req.db)
            .with(\.$dias)
            .sort(\.$hora)
            .all()

        return try timbres.map { timbre in
            TimbreDTO(
                id: try timbre.requireID(),
                etiqueta: timbre.etiqueta,
                hora: timbre.hora,
                duracionSeg: timbre.duracionSeg,
                activo: timbre.activo,
                dias: timbre.dias.map(\.dia).ordenados()
            )
        }
    }

    /// F-02: los toques de hoy según el horario vigente. Si hay un horario
    /// especial cubriendo la fecha, manda él (RF-10); si no, el habitual.
    func hoy(req: Request) async throws -> TimbresHoyResponse {
        let horaActual = FormatoTiempo.horaActual()
        guard let dia = FormatoTiempo.diaDeHoy() else {
            // Domingo: no hay timbres que mostrar.
            return TimbresHoyResponse(
                fuente: "habitual", nombreEspecial: nil, dia: nil,
                horaServidor: horaActual, timbres: [], proximo: nil
            )
        }

        let hoyISO = FormatoTiempo.hoyISO()

        // ¿Rige un horario especial? (RF-12: al vencer la fecha fin deja de
        // aparecer aquí solo, sin ningún proceso que lo apague.)
        let especial = try await HorarioEspecial.query(on: req.db)
            .filter(\.$activo == true)
            .filter(\.$fechaInicio <= hoyISO)
            .filter(\.$fechaFin >= hoyISO)
            .sort(\.$creadoAt, .descending)
            .with(\.$timbres) { $0.with(\.$dias) }
            .first()

        let delDia: [TimbreDelDiaDTO]
        if let especial {
            delDia = try especial.timbres
                .filter { $0.dias.contains { $0.dia == dia } }
                .map { TimbreDelDiaDTO(id: try $0.requireID(), etiqueta: $0.etiqueta, hora: $0.hora, duracionSeg: $0.duracionSeg) }
                .sorted { $0.hora < $1.hora }
        } else {
            let habituales = try await HorarioTimbre.query(on: req.db)
                .filter(\.$activo == true)
                .with(\.$dias)
                .sort(\.$hora)
                .all()
            delDia = try habituales
                .filter { $0.dias.contains { $0.dia == dia } }
                .map { TimbreDelDiaDTO(id: try $0.requireID(), etiqueta: $0.etiqueta, hora: $0.hora, duracionSeg: $0.duracionSeg) }
        }

        return TimbresHoyResponse(
            fuente: especial == nil ? "habitual" : "especial",
            nombreEspecial: especial?.nombre,
            dia: dia,
            horaServidor: horaActual,
            timbres: delDia,
            proximo: delDia.first { $0.hora >= horaActual }
        )
    }

    /// RF-09: crear timbre habitual. Solo administrador.
    func crear(req: Request) async throws -> TimbreDTO {
        try req.exigirRol(.admin)
        let datos = try req.content.decode(GuardarTimbreRequest.self)
        try validar(datos)

        let timbre = HorarioTimbre(
            etiqueta: datos.etiqueta.trimmingCharacters(in: .whitespacesAndNewlines),
            hora: datos.hora,
            duracionSeg: datos.duracionSeg ?? 5,
            activo: datos.activo ?? true
        )

        try await req.db.transaction { db in
            try await timbre.create(on: db)
            for dia in Set(datos.dias) {
                try await TimbreDia(timbreID: try timbre.requireID(), dia: dia).create(on: db)
            }
        }

        await EstadoModulo.compartido.notificarSincronizacion(motivo: "horario")
        return TimbreDTO(
            id: try timbre.requireID(),
            etiqueta: timbre.etiqueta,
            hora: timbre.hora,
            duracionSeg: timbre.duracionSeg,
            activo: timbre.activo,
            dias: datos.dias.ordenados()
        )
    }

    /// RF-09: editar. Los días se reemplazan completos, igual que las materias
    /// de un docente: la app manda el estado final del formulario.
    func editar(req: Request) async throws -> TimbreDTO {
        try req.exigirRol(.admin)
        let datos = try req.content.decode(GuardarTimbreRequest.self)
        try validar(datos)

        guard let timbre = try await HorarioTimbre.find(req.parameters.get("id"), on: req.db) else {
            throw Abort(.notFound, reason: "El timbre no existe")
        }

        try await req.db.transaction { db in
            timbre.etiqueta = datos.etiqueta.trimmingCharacters(in: .whitespacesAndNewlines)
            timbre.hora = datos.hora
            timbre.duracionSeg = datos.duracionSeg ?? timbre.duracionSeg
            timbre.activo = datos.activo ?? timbre.activo
            try await timbre.save(on: db)

            let timbreID = try timbre.requireID()
            try await TimbreDia.query(on: db).filter(\.$timbre.$id == timbreID).delete()
            for dia in Set(datos.dias) {
                try await TimbreDia(timbreID: timbreID, dia: dia).create(on: db)
            }
        }

        await EstadoModulo.compartido.notificarSincronizacion(motivo: "horario")
        return TimbreDTO(
            id: try timbre.requireID(),
            etiqueta: timbre.etiqueta,
            hora: timbre.hora,
            duracionSeg: timbre.duracionSeg,
            activo: timbre.activo,
            dias: datos.dias.ordenados()
        )
    }

    /// RF-09: eliminar. Sus días caen en cascada; las activaciones históricas
    /// que lo referencian quedan con el id en null-able (FK sin cascade).
    func eliminar(req: Request) async throws -> HTTPStatus {
        try req.exigirRol(.admin)
        guard let timbre = try await HorarioTimbre.find(req.parameters.get("id"), on: req.db) else {
            throw Abort(.notFound, reason: "El timbre no existe")
        }
        try await timbre.delete(on: req.db)
        await EstadoModulo.compartido.notificarSincronizacion(motivo: "horario")
        return .noContent
    }

    private func validar(_ datos: GuardarTimbreRequest) throws {
        guard !datos.etiqueta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "La etiqueta es obligatoria")
        }
        try FormatoTiempo.validarHora(datos.hora)
        guard !datos.dias.isEmpty else {
            throw Abort(.badRequest, reason: "El timbre debe sonar al menos un día")
        }
        if let duracion = datos.duracionSeg, !(1...120).contains(duracion) {
            throw Abort(.badRequest, reason: "La duración debe estar entre 1 y 120 segundos")
        }
    }
}

extension Array where Element == DiaSemana {
    /// Lunes a sábado en orden calendario, no en orden de inserción.
    func ordenados() -> [DiaSemana] {
        DiaSemana.allCases.filter(contains)
    }
}
