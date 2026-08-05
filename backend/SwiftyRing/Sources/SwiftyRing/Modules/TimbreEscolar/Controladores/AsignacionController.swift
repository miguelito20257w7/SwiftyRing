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

/// Un bloque visto desde el docente y no desde el salón: el profesor está
/// implícito y el salón pasa a ser el dato que se elige.
///
/// Es el mismo `Bloque` de la base que devuelve [BloqueDTO]; cambia qué se
/// deja fijo y qué se edita, porque armar el horario de un docente y armar el
/// de un salón son la misma tabla mirada desde dos lados.
struct BloqueDocenteDTO: Content {
    let id: UUID
    let horaInicio: String
    let horaFin: String
    let materiaId: UUID
    let materiaNombre: String
    let salonId: UUID
    let salonNombre: String
}

struct HorarioDocenteDiaDTO: Content {
    let profesorId: UUID
    let dia: DiaSemana
    let bloques: [BloqueDocenteDTO]
}

struct GuardarBloqueDocenteRequest: Content {
    let horaInicio: String
    let horaFin: String
    let materiaId: UUID
    let salonId: UUID
}

struct GuardarHorarioDocenteRequest: Content {
    let bloques: [GuardarBloqueDocenteRequest]
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

        // La otra cara de RF-34: el mismo horario armado desde el docente en
        // vez de desde el salón.
        api.get("profesores", ":profesorId", "horario", ":dia", use: horarioDeProfesorEnDia)
        api.put("profesores", ":profesorId", "horario", ":dia", use: guardarHorarioDeProfesor)
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

    /// Las clases de un docente en un día, con los ids que hacen falta para
    /// editarlas. `/profesores/:id/horario` devuelve la semana con nombres
    /// para pintar; esto devuelve un día con ids para modificar.
    func horarioDeProfesorEnDia(req: Request) async throws -> HorarioDocenteDiaDTO {
        try req.exigirRol(.admin)
        let (profesorID, dia) = try await parametrosDeProfesor(req)

        let bloques = try await Bloque.query(on: req.db)
            .filter(\.$profesorID == profesorID)
            .with(\.$horarioSalon)
            .all()
            .filter { $0.horarioSalon.dia == dia }
            .sorted { $0.horaInicio < $1.horaInicio }

        return HorarioDocenteDiaDTO(
            profesorId: profesorID,
            dia: dia,
            bloques: try await nombrarParaDocente(bloques, on: req.db)
        )
    }

    /// RF-35 desde el docente: reemplaza sus clases de ese día con el estado
    /// final del formulario.
    ///
    /// A diferencia del guardado por salón, esto **escribe en salones que el
    /// administrador no está mirando**, y de ahí salen las tres precauciones:
    /// solo se borran los bloques de *este* docente (los de sus compañeros en
    /// esos mismos salones no se tocan), se rechaza el choque con una clase ya
    /// existente en el salón de destino, y al final se renumera cada salón
    /// afectado, porque `numero` es el orden dentro del salón y meter una
    /// clase a media mañana corre el resto.
    func guardarHorarioDeProfesor(req: Request) async throws -> HorarioDocenteDiaDTO {
        try req.exigirRol(.admin)
        let (profesorID, dia) = try await parametrosDeProfesor(req)
        let datos = try req.content.decode(GuardarHorarioDocenteRequest.self)
        try validar(datos)

        try await req.db.transaction { db in
            var horarioPorSalon: [UUID: HorarioSalon] = [:]
            for horario in try await HorarioSalon.query(on: db).filter(\.$dia == dia).all() {
                horarioPorSalon[horario.salonID] = horario
            }

            // Los salones cuya numeración habrá que rehacer: aquellos de los
            // que el docente sale y aquellos a los que entra.
            var afectados = Set<UUID>()

            let idsDelDia = try horarioPorSalon.values.map { try $0.requireID() }
            if !idsDelDia.isEmpty {
                let previos = try await Bloque.query(on: db)
                    .filter(\.$profesorID == profesorID)
                    .filter(\.$horarioSalon.$id ~~ idsDelDia)
                    .all()
                afectados.formUnion(previos.map { $0.$horarioSalon.id })

                for bloque in previos {
                    try await bloque.delete(on: db)
                }
            }

            for nuevo in datos.bloques {
                let horario: HorarioSalon
                if let existente = horarioPorSalon[nuevo.salonId] {
                    horario = existente
                } else {
                    guard try await Salon.find(nuevo.salonId, on: db) != nil else {
                        throw Abort(.notFound, reason: "El salón no existe")
                    }
                    let creado = HorarioSalon(salonID: nuevo.salonId, dia: dia)
                    try await creado.create(on: db)
                    horarioPorSalon[nuevo.salonId] = creado
                    horario = creado
                }
                let horarioID = try horario.requireID()

                // Lo que ya hay en ese salón a esa hora: puede ser la clase de
                // otro docente, que este formulario no muestra.
                let ocupados = try await Bloque.query(on: db)
                    .filter(\.$horarioSalon.$id == horarioID)
                    .all()
                if let choque = ocupados.first(where: {
                    nuevo.horaInicio < $0.horaFin && $0.horaInicio < nuevo.horaFin
                }) {
                    let salon = try await Salon.find(nuevo.salonId, on: db)
                    throw Abort(
                        .conflict,
                        reason: "\(salon?.nombre ?? "El salón") ya tiene clase de "
                            + "\(choque.horaInicio) a \(choque.horaFin) ese día"
                    )
                }

                // El número real se asigna en el repaso de abajo.
                try await Bloque(
                    horarioSalonID: horarioID,
                    numero: 1,
                    horaInicio: nuevo.horaInicio,
                    horaFin: nuevo.horaFin,
                    materiaID: nuevo.materiaId,
                    profesorID: profesorID
                ).create(on: db)

                afectados.insert(horarioID)
            }

            for horarioID in afectados {
                let bloques = try await Bloque.query(on: db)
                    .filter(\.$horarioSalon.$id == horarioID)
                    .all()
                    .sorted { $0.horaInicio < $1.horaInicio }
                for (indice, bloque) in bloques.enumerated() {
                    bloque.numero = indice + 1
                    try await bloque.save(on: db)
                }
            }
        }

        return try await horarioDeProfesorEnDia(req: req)
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

    private func parametrosDeProfesor(_ req: Request) async throws -> (UUID, DiaSemana) {
        guard let diaTexto = req.parameters.get("dia"),
              let dia = DiaSemana(rawValue: diaTexto)
        else {
            throw Abort(.badRequest, reason: "Día inválido; usar lunes…sabado")
        }
        guard let profesorID: UUID = req.parameters.get("profesorId"),
              let profesor = try await Usuario.find(profesorID, on: req.db),
              profesor.rol == .profesor
        else {
            throw Abort(.notFound, reason: "El docente no existe")
        }
        return (try profesor.requireID(), dia)
    }

    private func nombrarParaDocente(_ bloques: [Bloque], on db: any Database) async throws -> [BloqueDocenteDTO] {
        let materias = try await Materia.query(on: db).all()
        let materiaPorID = Dictionary(uniqueKeysWithValues: try materias.map { (try $0.requireID(), $0.nombre) })
        let salones = try await Salon.query(on: db).all()
        let salonPorID = Dictionary(uniqueKeysWithValues: try salones.map { (try $0.requireID(), $0.nombre) })

        return try bloques.map { bloque in
            BloqueDocenteDTO(
                id: try bloque.requireID(),
                horaInicio: bloque.horaInicio,
                horaFin: bloque.horaFin,
                materiaId: bloque.materiaID,
                materiaNombre: materiaPorID[bloque.materiaID] ?? "—",
                salonId: bloque.horarioSalon.salonID,
                salonNombre: salonPorID[bloque.horarioSalon.salonID] ?? "—"
            )
        }
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

    private func validar(_ datos: GuardarHorarioDocenteRequest) throws {
        for bloque in datos.bloques {
            try FormatoTiempo.validarHora(bloque.horaInicio)
            try FormatoTiempo.validarHora(bloque.horaFin)
            guard bloque.horaInicio < bloque.horaFin else {
                throw Abort(
                    .badRequest,
                    reason: "El bloque de las \(bloque.horaInicio) termina antes de empezar"
                )
            }
        }

        // Una persona no está en dos salones a la vez. El formulario por salón
        // no puede comprobar esto —solo ve un salón—, así que es propio de
        // este modo.
        let ordenados = datos.bloques.sorted { $0.horaInicio < $1.horaInicio }
        for (anterior, siguiente) in zip(ordenados, ordenados.dropFirst()) {
            guard anterior.horaFin <= siguiente.horaInicio else {
                throw Abort(
                    .badRequest,
                    reason: "El docente no puede estar en dos clases a la vez: "
                        + "\(anterior.horaInicio)–\(anterior.horaFin) se cruza con "
                        + "\(siguiente.horaInicio)–\(siguiente.horaFin)"
                )
            }
        }
    }
}
