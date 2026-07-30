import Fluent
import Vapor

/// Composición de rutas.
///
/// Igual que `main.dart` en la app Flutter, este archivo es el **único** que
/// conoce a la vez el núcleo y todos los módulos. `Core` no sabe qué módulos
/// existen; cada módulo no sabe de los demás.
///
/// Añadir un módulo es una línea aquí; quitarlo, borrar esa línea y su carpeta.
func routes(_ app: Application) throws {
    // Sonda de vida, útil para comprobar que el servicio está arriba.
    app.get { _ async in "SwiftyRing · API del Sistema de Timbre Escolar" }

    try Core.registrarRutas(app)
    try TimbreEscolar.registrarRutas(app)
}
