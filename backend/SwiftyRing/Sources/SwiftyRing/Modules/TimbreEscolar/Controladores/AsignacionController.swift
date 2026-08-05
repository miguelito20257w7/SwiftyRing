//
//  AsignacionController.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  El horario académico: por salón y día para el administrador (F-06,
//  RF-34/RF-35) y la vista "mi horario" del profesor autenticado (RF-40).
//

import Vapor
import Fluent

struct BloqueDTO: Content {
    let id: UUID
    let numero: Int
    let horaInicio: String
    let horaFin: String
    let materiaId: UUID
    let materiaNombre: String
    let profesorId: UUID
    let profesorNombre: String
}

struct HorarioSalonDTO: Content {
    let salonId: UUID
    let dia: DiaSemana
    let bloques: [BloqueDTO]
}

struct GuardarBloqueRequest: Content {
    let numero: Int
    let horaInicio: String
    let horaFin: String
    let materiaId: UUID
    let profesorId: UUID
}

struct GuardarHorarioSalonRequest: Content {
    let bloques: [GuardarBloqueRequest]
}

/// Un bloque en la vista del profesor: sin ids, con nombres, listo para pintar.
struct MiBloqueDTO: Content {
    let numero: Int
    let horaInicio: String
    let horaFin: String
    let materia: String
    let salon: String
}

struct MiDiaDTO: Content {
    let dia: DiaSemana
    let bloques: [MiBloqueDTO]
}

struct MiHorarioResponse: Content {
    /// Día actual en Colombia; `nil` el domingo. La app lo usa para marcar
    /// "En curso" y "Próxima" (RF-41, RF-42) sin fiarse del reloj del teléfono.
    let diaActual: DiaSemana?
    let horaServidor: String
    let dias: [MiDiaDTO]
}

struct AsignacionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let api = routes.grouped("api").grouped(SwiftyRingAuthMiddleware())

        api.get("salones", ":salonId", "horario", ":dia", use: horarioDeSalon)
        api.put("salones", ":salonId", "horario", ":dia", use: guardarHorarioDeSalon)
        api.get("mi-horario", use: miHorario)
        api.get("profesores", ":profesorId", "horario", use: horarioDeProfesor)
    }

    /// El horario de un salón para un día. Sin bloques todavía no es un error:
    /// es un formulario vacío.
    func horarioDeSalon(req: Request) async throws -> HorarioSalonDTO {
        try req.exigirRol(.admin)
        let (salonID, dia) = try await parametros(req)

        guard let horario = try await HorarioSalon.query(on: req.db)
            .filter(\.$salonID == salonID)
            .filter(\.$dia == dia)
            .with(\.$bloques)
            .first()
        else {
            return HorarioSalonDTO(salonId: salonID, dia: dia, bloques: [])
        }

        return HorarioSalonDTO(
            salonId: salonID,
            dia: dia,
            bloques: try await nombrar(horario.bloques.sorted { $0.numero < $1.numero }, on: req.db)
        )
    }

    /// RF-35: reemplaza el horario del salón para ese día con el estado final
    /// del formulario. Crea la cabecera si no existía.
    func guardarHorarioDeSalon(req: Request) async throws -> HorarioSalonDTO {
        try req.exigirRol(.admin)
        let (salonID, dia) = try await parametros(req)
        let datos = try req.content.decode(GuardarHorarioSalonRequest.self)
        try validar(datos)

        try await req.db.transaction { db in
            let horario: HorarioSalon
            if let existente = try await HorarioSalon.query(on: db)
                .filter(\.$salonID == salonID)
                .filter(\.$dia == dia)
                .first() {
                horario = existente
            } else {
                horario = HorarioSalon(salonID: salonID, dia: dia)
                try await horario.create(on: db)
            }

            let horarioID = try horario.requireID()
            try await Bloque.query(on: db)
                .filter(\.$horarioSalon.$id == horarioID)
                .delete()

            for bloque in datos.bloques {
                try await Bloque(
                    horarioSalonID: horarioID,
                    numero: bloque.numero,
                    horaInicio: bloque.horaInicio,
                    horaFin: bloque.horaFin,
                    materiaID: bloque.materiaId,
                    profesorID: bloque.profesorId
                ).create(on: db)
            }
        }

        return try await horarioDeSalon(req: req)
    }

    /// RF-40: el horario semanal completo del profesor autenticado, agrupado
    /// por día y ordenado por hora.
    func miHorario(req: Request) async throws -> MiHorarioResponse {
        let payload = try req.exigirRol(.profesor)
        guard let profesorID = payload.usuarioID else {
            throw Abort(.unauthorized, reason: "Sesión no válida")
        }
        return try await horarioSemanal(de: profesorID, on: req.db)
    }

    /// La distribución semanal de un docente concreto, para la vista de
    /// detalle en Gestión de Docentes (F-05, frame "Asignación Horaria" del
    /// prototipo). Misma forma que `/mi-horario`: la app pinta ambas con el
    /// mismo modelo.
    func horarioDeProfesor(req: Request) async throws -> MiHorarioResponse {
        try req.exigirRol(.admin)

        guard let profesorID: UUID = req.parameters.get("profesorId"),
              let profesor = try await Usuario.find(profesorID, on: req.db),
              profesor.rol == .profesor
        else {
            throw Abort(.notFound, reason: "El docente no existe")
        }

        return try await horarioSemanal(de: profesorID, on: req.db)
    }

    /// El armado común de las dos rutas de arriba.
    private func horarioSemanal(de profesorID: UUID, on db: any Database) async throws -> MiHorarioResponse {
        let bloques = try await Bloque.query(on: db)
            .filter(\.$profesorID == profesorID)
            .with(\.$horarioSalon)
            .all()

        let materias = try await Materia.query(on: db).all()
        let materiaPorID = Dictionary(uniqueKeysWithValues: try materias.map { (try $0.requireID(), $0.nombre) })
        let salones = try await Salon.query(on: db).all()
        let salonPorID = Dictionary(uniqueKeysWithValues: try salones.map { (try $0.requireID(), $0.nombre) })

        let dias = DiaSemana.allCases.compactMap { dia -> MiDiaDTO? in
            let delDia = bloques
                .filter { $0.horarioSalon.dia == dia && $0.horarioSalon.activo }
                .sorted { $0.horaInicio < $1.horaInicio }
                .map { bloque in
                    MiBloqueDTO(
                        numero: bloque.numero,
                        horaInicio: bloque.horaInicio,
                        horaFin: bloque.horaFin,
                        materia: materiaPorID[bloque.materiaID] ?? "—",
                        salon: salonPorID[bloque.horarioSalon.salonID] ?? "—"
                    )
                }
            // Un día sin clases no aparece: la vista del profesor lista
            // jornadas reales, no huecos.
            return delDia.isEmpty ? nil : MiDiaDTO(dia: dia, bloques: delDia)
        }

        return MiHorarioResponse(
            diaActual: FormatoTiempo.diaDeHoy(),
            horaServidor: FormatoTiempo.horaActual(),
            dias: dias
        )
    }

    // MARK: - Apoyo

    private func parametros(_ req: Request) async throws -> (UUID, DiaSemana) {
        guard let diaTexto = req.parameters.get("dia"),
              let dia = DiaSemana(rawValue: diaTexto)
        else {
            throw Abort(.badRequest, reason: "Día inválido; usar lunes…sabado")
        }
        guard let salonID: UUID = req.parameters.get("salonId"),
              let salon = try await Salon.find(salonID, on: req.db)
        else {
            throw Abort(.notFound, reason: "El salón no existe")
        }
        return (try salon.requireID(), dia)
    }

    private func nombrar(_ bloques: [Bloque], on db: any Database) async throws -> [BloqueDTO] {
        let materias = try await Materia.query(on: db).all()
        let materiaPorID = Dictionary(uniqueKeysWithValues: try materias.map { (try $0.requireID(), $0.nombre) })
        let profesores = try await Usuario.query(on: db).filter(\.$rol == .profesor).all()
        let profesorPorID = Dictionary(uniqueKeysWithValues: try profesores.map { (try $0.requireID(), $0.nombre) })

        return try bloques.map { bloque in
            BloqueDTO(
                id: try bloque.requireID(),
                numero: bloque.numero,
                horaInicio: bloque.horaInicio,
                horaFin: bloque.horaFin,
                materiaId: bloque.materiaID,
                materiaNombre: materiaPorID[bloque.materiaID] ?? "—",
                profesorId: bloque.profesorID,
                profesorNombre: profesorPorID[bloque.profesorID] ?? "—"
            )
        }
    }

    private func validar(_ datos: GuardarHorarioSalonRequest) throws {
        for bloque in datos.bloques {
            try FormatoTiempo.validarHora(bloque.horaInicio)
            try FormatoTiempo.validarHora(bloque.horaFin)
            guard bloque.horaInicio < bloque.horaFin else {
                throw Abort(.badRequest, reason: "El bloque \(bloque.numero) termina antes de empezar")
            }
            guard bloque.numero >= 1 else {
                throw Abort(.badRequest, reason: "El número de bloque empieza en 1")
            }
        }
    }
}
