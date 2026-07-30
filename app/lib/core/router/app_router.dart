import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/core/auth/presentation/pages/cargando_page.dart';
import 'package:swiftyring/core/auth/presentation/pages/login_page.dart';
import 'package:swiftyring/core/auth/presentation/pages/welcome_page.dart';
import 'package:swiftyring/core/modulos/lanzador_page.dart';
import 'package:swiftyring/core/modulos/modulo_app.dart';
import 'package:swiftyring/core/red/presentation/ajustes_red_page.dart';
import 'package:swiftyring/core/router/rutas.dart';

/// Construye el router de la aplicación.
///
/// **`core/` no conoce los módulos.** Llegan por parámetro desde `main.dart`,
/// que es la raíz de composición, descritos como [ModuloApp]. De esa única
/// lista salen dos cosas: las tarjetas del lanzador y las rutas del router.
///
/// Eliminar un módulo son dos pasos, ambos fuera de `core/`: borrar su carpeta
/// y quitar su línea en `main.dart`.
GoRouter crearRouter(Ref ref, {required List<ModuloApp> modulos}) {
  return GoRouter(
    initialLocation: Rutas.cargando,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: _EscuchaDeSesion(ref),
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final destino = state.matchedLocation;

      // Mientras se lee el almacenamiento seguro no se decide nada: mandar al
      // login aquí haría parpadear la bienvenida a quien sí tenía sesión.
      if (auth.estado == EstadoSesion.restaurando) {
        return destino == Rutas.cargando ? null : Rutas.cargando;
      }

      if (!auth.autenticado) {
        return Rutas.publicas.contains(destino) && destino != Rutas.cargando
            ? null
            : Rutas.bienvenida;
      }

      // Ya autenticado: las pantallas de entrada dejan de tener sentido y se
      // sustituyen por el lanzador. Ajustes de red no: la dirección del
      // servidor se corrige con sesión o sin ella.
      return Rutas.publicas.contains(destino) &&
              !Rutas.conYSinSesion.contains(destino)
          ? Rutas.lanzador
          : null;
    },
    routes: [
      GoRoute(
        path: Rutas.cargando,
        builder: (context, state) => const CargandoPage(),
      ),
      GoRoute(
        path: Rutas.bienvenida,
        builder: (context, state) => const WelcomePage(),
      ),
      GoRoute(
        path: Rutas.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: Rutas.ajustesRed,
        builder: (context, state) => const AjustesRedPage(),
      ),
      GoRoute(
        path: Rutas.lanzador,
        builder: (context, state) => LanzadorPage(modulos: modulos),
      ),
      // Cada módulo aporta las suyas; el router no sabe cuáles son.
      for (final modulo in modulos) ...modulo.rutas,
    ],
  );
}

/// Avisa a go_router cada vez que cambia el estado de sesión, para que vuelva
/// a evaluar el `redirect`.
class _EscuchaDeSesion extends ChangeNotifier {
  late final ProviderSubscription<AuthState> _suscripcion;

  _EscuchaDeSesion(Ref ref) {
    _suscripcion = ref.listen<AuthState>(authProvider, (anterior, actual) {
      // Solo interesa el cambio de sesión. Redibujar en cada pulsación de
      // tecla del formulario sería trabajo perdido.
      if (anterior?.estado != actual.estado) notifyListeners();
    });
  }

  @override
  void dispose() {
    _suscripcion.close();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  throw UnimplementedError(
    'Sobrescribe routerProvider en main.dart con la lista de módulos.',
  );
});
