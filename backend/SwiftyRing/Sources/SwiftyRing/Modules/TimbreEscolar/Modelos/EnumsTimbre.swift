//
//  EnumsTimbre.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  Tipos enumerados del dominio del timbre (SketchBD.dbml v5). `rol_usuario`
//  no está aquí: pertenece a Core/Identidad.
//

import Foundation

/// Origen de cada activación del timbre (RF-17).
enum TipoActivacion: String, Codable, Sendable {
    case automatico
    case manualApp = "manual_app"
    case manualFisico = "manual_fisico"
    case sismico
}

/// Días que soporta el sistema (RF-08). La operación regular del colegio es de
/// lunes a viernes; el sábado existe para jornadas extraordinarias.
enum DiaSemana: String, Codable, Sendable, CaseIterable {
    case lunes, martes, miercoles, jueves, viernes, sabado

    /// El día que corresponde a una fecha, o `nil` si es domingo (el sistema
    /// no programa timbres los domingos).
    static func de(_ fecha: Date, calendario: Calendar = .current) -> DiaSemana? {
        // weekday de Foundation: 1 = domingo ... 7 = sábado.
        switch calendario.component(.weekday, from: fecha) {
        case 2: return .lunes
        case 3: return .martes
        case 4: return .miercoles
        case 5: return .jueves
        case 6: return .viernes
        case 7: return .sabado
        default: return nil
        }
    }
}

/// Plataforma del dispositivo registrado para push.
enum Plataforma: String, Codable, Sendable {
    case ios, android, web
}

/// Jornada laboral del profesor.
enum Jornada: String, Codable, Sendable {
    case manana, tarde, completa
}
