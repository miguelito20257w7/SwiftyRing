//
//  Catalogos.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  Catálogos parametrizables de la institución: materias y salones. Existen
//  para que la solución sea replicable a otros colegios sin tocar código.
//

import Fluent
import Foundation

final class Materia: Model, @unchecked Sendable {
    static let schema = "materias"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "nombre")
    var nombre: String

    /// Retirar una materia del catálogo sin borrarla: los bloques históricos
    /// que la referencian siguen siendo válidos.
    @Field(key: "activo")
    var activo: Bool

    init() { }

    init(nombre: String, activo: Bool = true) {
        self.nombre = nombre
        self.activo = activo
    }
}

final class Salon: Model, @unchecked Sendable {
    static let schema = "salones"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "nombre")
    var nombre: String

    /// Bloque físico del colegio (ej. "Bloque A").
    @OptionalField(key: "bloque")
    var bloque: String?

    @OptionalField(key: "piso")
    var piso: Int?

    @OptionalField(key: "capacidad")
    var capacidad: Int?

    @Field(key: "activo")
    var activo: Bool

    init() { }

    init(nombre: String, bloque: String? = nil, piso: Int? = nil, capacidad: Int? = nil, activo: Bool = true) {
        self.nombre = nombre
        self.bloque = bloque
        self.piso = piso
        self.capacidad = capacidad
        self.activo = activo
    }
}
