//
//  MigracionesTimbreEscolar.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  Las 15 tablas del dominio del timbre (SketchBD.dbml v5). `usuarios` no está
//  aquí: es de Core. El orden de los structs es el orden de aplicación, porque
//  las llaves foráneas exigen que el padre exista primero.
//
//  Los índices de consulta con nombre propio en el modelo (idx_disp_usuario,
//  idx_especial_vigencia, …) se crean con SQL directo: el schema builder de
//  Fluent solo sabe de restricciones únicas.
//

import Fluent
import FluentSQL
import SQLKit

/// Crea un índice si el motor es SQL (en los tests con SQLite en memoria u
/// otros motores simplemente no se crea; es una ayuda de rendimiento, no una
/// regla de integridad).
private func crearIndice(_ nombre: String, tabla: String, columnas: String, on database: any Database) async throws {
    guard let sql = database as? any SQLDatabase else { return }
    try await sql.raw("CREATE INDEX IF NOT EXISTS \(unsafeRaw: nombre) ON \(unsafeRaw: tabla) (\(unsafeRaw: columnas))").run()
}

private func borrarIndice(_ nombre: String, on database: any Database) async throws {
    guard let sql = database as? any SQLDatabase else { return }
    try await sql.raw("DROP INDEX IF EXISTS \(unsafeRaw: nombre)").run()
}

// MARK: - Catálogos

struct CreateCatalogosTimbre: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Materia.schema)
            .id()
            .field("nombre", .string, .required)
            .field("activo", .bool, .required)
            .unique(on: "nombre")
            .create()

        try await database.schema(Salon.schema)
            .id()
            .field("nombre", .string, .required)
            .field("bloque", .string)
            .field("piso", .int)
            .field("capacidad", .int)
            .field("activo", .bool, .required)
            .unique(on: "nombre")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Salon.schema).delete()
        try await database.schema(Materia.schema).delete()
    }
}

// MARK: - Profesores

struct CreateProfesores: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let jornada = try await database.enum("jornada")
            .case("manana")
            .case("tarde")
            .case("completa")
            .create()

        // PK = FK 1:1 hacia usuarios: si se borra la cuenta, cae el perfil.
        try await database.schema(Profesor.schema)
            .field("usuario_id", .uuid, .identifier(auto: false),
                   .references("usuarios", "id", onDelete: .cascade))
            .field("jornada", jornada, .required)
            .field("director_de_grupo", .string)
            .field("creado_at", .datetime, .required)
            .unique(on: "director_de_grupo")
            .create()

        try await database.schema(ProfesorMateria.schema)
            .id()
            .field("profesor_id", .uuid, .required,
                   .references("profesores", "usuario_id", onDelete: .cascade))
            .field("materia_id", .uuid, .required,
                   .references("materias", "id", onDelete: .cascade))
            .unique(on: "profesor_id", "materia_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(ProfesorMateria.schema).delete()
        try await database.schema(Profesor.schema).delete()
        try await database.enum("jornada").delete()
    }
}

// MARK: - Dispositivos

struct CreateDispositivos: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let plataforma = try await database.enum("plataforma")
            .case("ios")
            .case("android")
            .case("web")
            .create()

        try await database.schema(Dispositivo.schema)
            .id()
            .field("usuario_id", .uuid, .required,
                   .references("usuarios", "id", onDelete: .cascade))
            .field("plataforma", plataforma, .required)
            .field("fcm_token", .string, .required)
            .field("nombre_dispositivo", .string)
            .field("activo", .bool, .required)
            .field("registrado_at", .datetime, .required)
            .field("ultimo_uso_at", .datetime)
            .unique(on: "fcm_token")
            .create()

        try await crearIndice("idx_disp_usuario", tabla: Dispositivo.schema, columnas: "usuario_id", on: database)
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Dispositivo.schema).delete()
        try await database.enum("plataforma").delete()
    }
}

// MARK: - Horario habitual

struct CreateHorarioTimbres: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let diaSemana = try await database.enum("dia_semana")
            .case("lunes")
            .case("martes")
            .case("miercoles")
            .case("jueves")
            .case("viernes")
            .case("sabado")
            .create()

        try await database.schema(HorarioTimbre.schema)
            .id()
            .field("etiqueta", .string, .required)
            .field("hora", .string, .required)
            .field("duracion_seg", .int, .required)
            .field("activo", .bool, .required)
            .field("creado_at", .datetime, .required)
            .create()

        try await database.schema(TimbreDia.schema)
            .id()
            .field("timbre_id", .uuid, .required,
                   .references("horario_timbres", "id", onDelete: .cascade))
            .field("dia", diaSemana, .required)
            .unique(on: "timbre_id", "dia")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(TimbreDia.schema).delete()
        try await database.schema(HorarioTimbre.schema).delete()
        try await database.enum("dia_semana").delete()
    }
}

// MARK: - Horarios especiales

struct CreateHorariosEspeciales: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let diaSemana = try await database.enum("dia_semana").read()

        try await database.schema(HorarioEspecial.schema)
            .id()
            .field("nombre", .string, .required)
            .field("fecha_inicio", .string, .required)
            .field("fecha_fin", .string, .required)
            .field("activo", .bool, .required)
            .field("creado_por", .uuid, .required, .references("usuarios", "id"))
            .field("creado_at", .datetime, .required)
            .create()

        try await database.schema(TimbreEspecial.schema)
            .id()
            .field("horario_especial_id", .uuid, .required,
                   .references("horario_especial", "id", onDelete: .cascade))
            .field("etiqueta", .string, .required)
            .field("hora", .string, .required)
            .field("duracion_seg", .int, .required)
            .create()

        try await database.schema(TimbreEspecialDia.schema)
            .id()
            .field("timbre_especial_id", .uuid, .required,
                   .references("timbres_especiales", "id", onDelete: .cascade))
            .field("dia", diaSemana, .required)
            .unique(on: "timbre_especial_id", "dia")
            .create()

        try await crearIndice("idx_especial_vigencia", tabla: HorarioEspecial.schema,
                              columnas: "activo, fecha_inicio, fecha_fin", on: database)
    }

    func revert(on database: any Database) async throws {
        try await database.schema(TimbreEspecialDia.schema).delete()
        try await database.schema(TimbreEspecial.schema).delete()
        try await database.schema(HorarioEspecial.schema).delete()
    }
}

// MARK: - Asignación horaria

struct CreateAsignacion: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let diaSemana = try await database.enum("dia_semana").read()

        try await database.schema(HorarioSalon.schema)
            .id()
            .field("salon_id", .uuid, .required,
                   .references("salones", "id", onDelete: .cascade))
            .field("dia", diaSemana, .required)
            .field("activo", .bool, .required)
            .unique(on: "salon_id", "dia")
            .create()

        try await database.schema(Bloque.schema)
            .id()
            .field("horario_salon_id", .uuid, .required,
                   .references("horario_salon", "id", onDelete: .cascade))
            .field("numero", .int, .required)
            .field("hora_inicio", .string, .required)
            .field("hora_fin", .string, .required)
            .field("materia_id", .uuid, .required, .references("materias", "id"))
            .field("profesor_id", .uuid, .required,
                   .references("profesores", "usuario_id", onDelete: .cascade))
            .create()

        try await crearIndice("idx_bloques_profesor", tabla: Bloque.schema, columnas: "profesor_id", on: database)
        try await crearIndice("idx_bloques_horario", tabla: Bloque.schema, columnas: "horario_salon_id", on: database)
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Bloque.schema).delete()
        try await database.schema(HorarioSalon.schema).delete()
    }
}

// MARK: - Activaciones, sismos y notificaciones

struct CreateActivaciones: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let tipoActivacion = try await database.enum("tipo_activacion")
            .case("automatico")
            .case("manual_app")
            .case("manual_fisico")
            .case("sismico")
            .create()

        try await database.schema(ActivacionTimbre.schema)
            .id()
            .field("tipo", tipoActivacion, .required)
            .field("origen_usuario_id", .uuid, .references("usuarios", "id"))
            .field("ocurrido_at", .datetime, .required)
            .field("horario_timbre_id", .uuid, .references("horario_timbres", "id"))
            .field("duracion_seg", .int)
            .create()

        try await database.schema(EventoSismico.schema)
            .id()
            .field("activacion_id", .uuid, .references("activaciones_timbre", "id"))
            .field("intensidad_g", .double, .required)
            .field("duracion_ms", .int, .required)
            .field("ocurrido_at", .datetime, .required)
            .field("timbre_activado", .bool, .required)
            .field("notificacion_enviada", .bool, .required)
            .create()

        try await database.schema(NotificacionProfesor.schema)
            .id()
            .field("activacion_id", .uuid, .required,
                   .references("activaciones_timbre", "id", onDelete: .cascade))
            .field("profesor_id", .uuid, .required,
                   .references("profesores", "usuario_id", onDelete: .cascade))
            .field("bloque_id", .uuid, .required, .references("bloques", "id"))
            .field("mensaje", .string, .required)
            .field("enviada", .bool, .required)
            .field("enviada_at", .datetime)
            .create()

        try await crearIndice("idx_activaciones_fecha", tabla: ActivacionTimbre.schema, columnas: "ocurrido_at", on: database)
        try await crearIndice("idx_sismos_fecha", tabla: EventoSismico.schema, columnas: "ocurrido_at", on: database)
        try await crearIndice("idx_notif_profesor", tabla: NotificacionProfesor.schema, columnas: "profesor_id", on: database)
        try await crearIndice("idx_notif_activacion", tabla: NotificacionProfesor.schema, columnas: "activacion_id", on: database)
    }

    func revert(on database: any Database) async throws {
        try await database.schema(NotificacionProfesor.schema).delete()
        try await database.schema(EventoSismico.schema).delete()
        try await database.schema(ActivacionTimbre.schema).delete()
        try await database.enum("tipo_activacion").delete()
    }
}

// MARK: - Configuración (fila única)

struct CreateConfiguracionSistema: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(ConfiguracionSistema.schema)
            .field("id", .string, .identifier(auto: false))
            .field("nombre_colegio", .string)
            .field("umbral_sismico_g", .double, .required)
            .field("sismo_duracion_min_ms", .int, .required)
            .field("modo_offline", .bool, .required)
            .field("ultima_sync", .datetime)
            .create()

        // La fila única nace con la migración: la app nunca encuentra el
        // sistema sin configurar.
        let config = ConfiguracionSistema(nombreColegio: "I.E. Santa Sofía")
        try await config.create(on: database)
    }

    func revert(on database: any Database) async throws {
        try await database.schema(ConfiguracionSistema.schema).delete()
    }
}

struct AddModoUpsYDuracionManualAConfiguracion: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(ConfiguracionSistema.schema)
            .field("modo_ups", .bool, .sql(.default(false)))
            .field("duracion_timbre_manual_seg", .int, .sql(.default(5)))
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(ConfiguracionSistema.schema)
            .deleteField("modo_ups")
            .deleteField("duracion_timbre_manual_seg")
            .update()
    }
}

