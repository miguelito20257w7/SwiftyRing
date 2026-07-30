//
//  FormatoTiempo.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  Horas y fechas como texto ISO: `"HH:mm"` y `"yyyy-MM-dd"`. Ver la nota en
//  HorarioTimbre.swift sobre por qué el dominio las guarda así.
//

import Foundation
import Vapor

enum FormatoTiempo {

    /// Zona horaria de operación del sistema. El colegio vive en Colombia;
    /// el servidor puede vivir donde sea.
    static let zonaColombia = TimeZone(identifier: "America/Bogota")!

    private static var calendario: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zonaColombia
        return cal
    }

    /// ¿Es un `"HH:mm"` válido con cero a la izquierda? El cero importa: la
    /// comparación de horas es lexicográfica y "9:00" > "10:00" sería un bug.
    static func esHoraValida(_ texto: String) -> Bool {
        let partes = texto.split(separator: ":")
        guard partes.count == 2,
              partes[0].count == 2, partes[1].count == 2,
              let hora = Int(partes[0]), let minuto = Int(partes[1])
        else { return false }
        return (0..<24).contains(hora) && (0..<60).contains(minuto)
    }

    /// ¿Es un `"yyyy-MM-dd"` válido?
    static func esFechaValida(_ texto: String) -> Bool {
        let formato = DateFormatter()
        formato.dateFormat = "yyyy-MM-dd"
        formato.timeZone = zonaColombia
        return formato.date(from: texto) != nil
    }

    /// La hora actual en Colombia, `"HH:mm"`.
    static func horaActual(_ ahora: Date = Date()) -> String {
        let c = calendario.dateComponents([.hour, .minute], from: ahora)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// La fecha de hoy en Colombia, `"yyyy-MM-dd"`.
    static func hoyISO(_ ahora: Date = Date()) -> String {
        let c = calendario.dateComponents([.year, .month, .day], from: ahora)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// El día de la semana de hoy en Colombia, o `nil` si es domingo.
    static func diaDeHoy(_ ahora: Date = Date()) -> DiaSemana? {
        DiaSemana.de(ahora, calendario: calendario)
    }

    /// Corta con 400 si la hora no es válida.
    static func validarHora(_ texto: String) throws {
        guard esHoraValida(texto) else {
            throw Abort(.badRequest, reason: "Hora inválida: \"\(texto)\". Formato esperado HH:mm, ej. 07:30")
        }
    }

    static func validarFecha(_ texto: String) throws {
        guard esFechaValida(texto) else {
            throw Abort(.badRequest, reason: "Fecha inválida: \"\(texto)\". Formato esperado yyyy-MM-dd")
        }
    }
}
