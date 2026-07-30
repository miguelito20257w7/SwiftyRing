import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:swiftyring/core/auth/domain/rol_usuario.dart';
import 'package:swiftyring/core/modulos/modulo_app.dart';
import 'package:swiftyring/modules/proyecto_banos/presentation/pages/banos_inicio_page.dart';

/// Rutas del módulo Control Baños SS.
abstract class RutasBanos {
  static const inicio = '/banos';
}

/// Cómo se presenta este módulo en el lanzador.
///
/// **Este módulo pertenece a otro equipo** (Jhoan Santiago Chalarca, Isabel
/// Galeano, Juan Esteban Estrada) y debe poder eliminarse por completo sin que
/// el Sistema de Timbre Escolar deje de compilar:
///
/// ```bash
/// rm -rf lib/modules/proyecto_banos/
/// # y quitar su import y su línea en main.dart
/// flutter analyze && flutter test
/// ```
///
/// Solo puede importar desde `lib/core/`. Importar `modules/timbre_escolar/`
/// está prohibido y lo verifica `tool/check_module_isolation.sh`.
final ModuloApp proyectoBanosModulo = ModuloApp(
  id: 'control_banos',
  nombre: 'Control Baños SS',
  descripcion: 'Autorización y registro de salidas al baño',
  icono: Icons.meeting_room_outlined,
  // Azul Marino de la marca Control Baños SS (su RNF06). Marca independiente:
  // no comparte paleta con SwiftyRing.
  color: const Color(0xFF1E2545),
  rutaInicial: RutasBanos.inicio,
  // RF02 de su documento: el rol operador no tiene acceso, así que su tarjeta
  // no aparece siquiera en el lanzador.
  rolesPermitidos: const {RolUsuario.admin, RolUsuario.profesor},
  rutas: <RouteBase>[
    GoRoute(
      path: RutasBanos.inicio,
      builder: (context, state) => const BanosInicioPage(),
    ),
  ],
);
