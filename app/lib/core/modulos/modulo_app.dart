import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:swiftyring/core/auth/domain/rol_usuario.dart';

/// Descripción que un módulo da de sí mismo para aparecer en el lanzador.
///
/// Existe para resolver una tensión concreta: el lanzador tiene que **listar**
/// los módulos, pero vive en `core/`, y `core/` no puede importar módulos
/// (RNF-12). Si el lanzador tuviera dentro un `switch` con "timbre" y "baños",
/// borrar un módulo dejaría a `core/` sin compilar.
///
/// La solución es invertir quién conoce a quién: cada módulo construye su
/// propio [ModuloApp] y `main.dart` —la raíz de composición— pasa la lista.
/// `core/` solo ve una `List<ModuloApp>` que no sabe de dónde viene.
///
/// Lleva también sus [rutas], para que agregar o quitar un módulo sea un solo
/// cambio en un solo sitio en vez de dos listas que hay que mantener a la par.
@immutable
class ModuloApp {
  /// Identificador estable, para claves de widgets y analítica.
  final String id;

  /// Nombre visible en el lanzador.
  final String nombre;

  /// Una línea de qué hace. No más: el lanzador es una rejilla, no un manual.
  final String descripcion;

  final IconData icono;

  /// Color de acento propio del módulo. Cada módulo tiene su identidad visual;
  /// no comparten paleta (ver Documento Final, 2.1.4).
  final Color color;

  /// Ruta de su pantalla de entrada.
  final String rutaInicial;

  /// Roles que pueden entrar. Un rol fuera de este conjunto no ve la tarjeta.
  final Set<RolUsuario> rolesPermitidos;

  /// Las rutas que el módulo aporta al router.
  final List<RouteBase> rutas;

  const ModuloApp({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.icono,
    required this.color,
    required this.rutaInicial,
    required this.rolesPermitidos,
    required this.rutas,
  });

  bool permiteA(RolUsuario rol) => rolesPermitidos.contains(rol);
}
