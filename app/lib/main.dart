import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swiftyring/core/modulos/modulo_app.dart';
import 'package:swiftyring/core/red/servidor.dart';
import 'package:swiftyring/core/router/app_router.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/modules/proyecto_banos/proyecto_banos_routes.dart';
import 'package:swiftyring/modules/timbre_escolar/timbre_escolar_routes.dart';

/// Raíz de composición de la aplicación institucional.
///
/// Este es el **único** archivo que conoce a todos los módulos a la vez. Ni
/// `core/` ni `modules/timbre_escolar/` importan `modules/proyecto_banos/`
/// (RNF-12); la unión ocurre aquí y en ningún otro sitio.
///
/// Para eliminar un módulo de la app hacen falta dos pasos, y ninguno toca
/// `core/`:
///   1. borrar su carpeta bajo `lib/modules/`;
///   2. quitar su import y su línea en [modulosInstalados].
///
/// Lo verifica `tool/check_module_isolation.sh`.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // La dirección del servidor se lee del disco **antes** de montar nada. Si se
  // cargara dentro de un provider existiría un instante en que la app ya está
  // viva pero todavía no sabe a quién preguntarle, y cualquier petición que
  // cayera ahí iría al servidor equivocado.
  final servidor = await AlmacenServidor().leer();

  runApp(
    ProviderScope(
      overrides: [
        servidorInicialProvider.overrideWithValue(servidor),
        routerProvider.overrideWith(
          (ref) => crearRouter(ref, modulos: modulosInstalados),
        ),
      ],
      child: const SwiftyRingApp(),
    ),
  );
}

/// Las aplicaciones montadas en la plataforma.
///
/// De esta única lista salen dos cosas: las tarjetas del lanzador y las rutas
/// del router. Estaban en dos listas separadas y se juntaron para que agregar
/// un módulo no exija acordarse de tocar dos sitios.
///
/// Es pública a propósito: las pruebas la reutilizan en vez de repetirla.
final List<ModuloApp> modulosInstalados = [
  timbreEscolarModulo,
  proyectoBanosModulo, // ← módulo de otro equipo; esta línea es borrable
];

class SwiftyRingApp extends ConsumerWidget {
  const SwiftyRingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'SwiftyRing',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
