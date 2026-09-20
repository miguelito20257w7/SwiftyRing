//
//  TimbreEscolar.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  Punto de entrada del módulo de timbres: horarios, activaciones, sismos y
//  notificaciones a profesores.
//

import Vapor
import Fluent

/// El módulo del Sistema de Timbre Escolar.
///
/// Todo lo propio del dominio de timbres vive aquí: modelos, migraciones,
/// controladores y DTOs. Puede apoyarse en `Core` (identidad, JWT, middleware),
/// nunca al revés.
///
/// Registrar o quitar el módulo son dos líneas, ambas fuera de esta carpeta:
/// una en `configure.swift` (migraciones) y otra en `routes.swift` (rutas).
enum TimbreEscolar {

    /// Migraciones propias del módulo, en orden de aplicación: los padres de
    /// llave foránea van primero.
    static var migraciones: [any AsyncMigration] {
        [
            CreateCatalogosTimbre(),
            CreateProfesores(),
            CreateDispositivos(),
            CreateHorarioTimbres(),
            CreateHorariosEspeciales(),
            CreateAsignacion(),
            CreateActivaciones(),
            CreateConfiguracionSistema(),
            AddModoUpsYDuracionManualAConfiguracion(),
        ]
    }

    /// Rutas propias del módulo, todas bajo `/api` y detrás del middleware de
    /// autenticación de Core.
    static func registrarRutas(_ app: Application) throws {
        try app.register(collection: CatalogosController())
        try app.register(collection: ProfesoresController())
        try app.register(collection: TimbresController())
        try app.register(collection: HorariosEspecialesController())
        try app.register(collection: ActivacionesController())
        try app.register(collection: AsignacionController())
        try app.register(collection: ConfiguracionController())
        try app.register(collection: DispositivoController())
    }
}
