/// Rutas de `core/`: las que existen sin que ningún módulo esté montado.
///
/// Cada módulo declara las suyas en su propio archivo. `core/` no conoce las
/// rutas de ningún módulo (RNF-12).
abstract class Rutas {
  /// Pantalla de carga mientras se restaura la sesión guardada.
  static const cargando = '/';

  static const bienvenida = '/bienvenida';
  static const login = '/login';

  /// El lanzador: las aplicaciones a las que el usuario tiene acceso. Es el
  /// destino después de iniciar sesión, no la home de un módulo concreto.
  static const lanzador = '/apps';

  /// Rutas que un usuario sin sesión puede ver.
  static const publicas = {cargando, bienvenida, login};
}
