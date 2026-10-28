import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/core/auth/domain/rol_usuario.dart';
import 'package:swiftyring/core/modulos/modulo_app.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/ajustes_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/ajustes_profesor_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/asignacion_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/control_timbres_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/docente_detalle_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/docentes_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/editar_especial_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/editar_timbre_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/especiales_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/historial_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/horario_completo_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/mi_horario_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/setup_wizard_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/enganche_push.dart';

/// Rutas del módulo Sistema de Timbre Escolar.
abstract class RutasTimbre {
  static const inicio = '/timbre';
  static const editarTimbre = '/timbre/editar';
  static const especiales = '/timbre/especiales';
  static const editarEspecial = '/timbre/especiales/editar';
  static const docentes = '/timbre/docentes';
  static const asignacion = '/timbre/asignacion';
  static const miHorario = '/timbre/mi-horario';
  static const miHorarioCompleto = '/timbre/mi-horario/completo';
  static const historial = '/timbre/historial';
  static const ajustes = '/timbre/ajustes';
  static const setupWizard = '/timbre/setup-wizard';

  /// Los ajustes de solo lectura del profesor (F-09). Ruta aparte de
  /// [ajustes] porque son otra pantalla, no la misma con secciones ocultas:
  /// la de administración pide `/configuracion`, que a este rol le responde
  /// 403.
  static const misAjustes = '/timbre/mis-ajustes';

  /// Detalle de un docente con su distribución semanal (frame 1:392).
  static String docenteDetalle(String id) => '/timbre/docentes/$id';
}

/// Cómo se presenta este módulo en el lanzador.
///
/// El módulo se describe a sí mismo; `core/` no sabe que existe. Se compone en
/// `main.dart`, y este archivo no importa nada de `modules/proyecto_banos/`
/// (RNF-12).
final ModuloApp timbreEscolarModulo = ModuloApp(
  id: 'timbre_escolar',
  nombre: 'SwiftyRing',
  descripcion: 'Timbre escolar, horarios y alertas sísmicas',
  icono: Icons.notifications_active_outlined,
  // Dorado de la marca SwiftyRing.
  color: const Color(0xFF735C00),
  rutaInicial: RutasTimbre.inicio,
  // Los tres roles del sistema entran; lo que cambia es qué puede hacer cada
  // uno dentro, no si puede entrar.
  rolesPermitidos: const {
    RolUsuario.admin,
    RolUsuario.operador,
    RolUsuario.profesor,
  },
  rutas: <RouteBase>[
    GoRoute(
      path: RutasTimbre.inicio,
      builder: (context, state) => const _EntradaTimbre(),
    ),
    GoRoute(
      path: RutasTimbre.editarTimbre,
      builder: (context, state) =>
          EditarTimbrePage(timbre: state.extra as TimbreHabitual?),
    ),
    GoRoute(
      path: RutasTimbre.especiales,
      builder: (context, state) => const EspecialesPage(),
    ),
    GoRoute(
      path: RutasTimbre.editarEspecial,
      builder: (context, state) =>
          EditarEspecialPage(horario: state.extra as HorarioEspecial?),
    ),
    GoRoute(
      path: RutasTimbre.docentes,
      builder: (context, state) => const DocentesPage(),
    ),
    GoRoute(
      // El id va en la ruta y el docente en `extra`: con el id la página se
      // puede reconstruir sola (recarga tras editar); el extra le ahorra el
      // parpadeo de carga al llegar desde la lista.
      path: '/timbre/docentes/:id',
      builder: (context, state) => DocenteDetallePage(
        docenteId: state.pathParameters['id']!,
        inicial: state.extra as Docente?,
      ),
    ),
    GoRoute(
      path: RutasTimbre.asignacion,
      builder: (context, state) => const AsignacionPage(),
    ),
    GoRoute(
      path: RutasTimbre.miHorario,
      builder: (context, state) => const MiHorarioPage(),
    ),
    GoRoute(
      path: RutasTimbre.miHorarioCompleto,
      builder: (context, state) => const HorarioCompletoPage(),
    ),
    GoRoute(
      path: RutasTimbre.historial,
      builder: (context, state) => const HistorialPage(),
    ),
    GoRoute(
      path: RutasTimbre.ajustes,
      builder: (context, state) => const AjustesPage(),
    ),
    GoRoute(
      path: RutasTimbre.setupWizard,
      builder: (context, state) => const SetupWizardPage(),
    ),
    GoRoute(
      path: RutasTimbre.misAjustes,
      builder: (context, state) => const AjustesProfesorPage(),
    ),
  ],
);

/// La puerta del módulo reparte por rol (P-01): el profesor va directo a su
/// horario (RF-40); administrador y operador, al control de timbres (F-02).
///
/// Es también donde se engancha el push: al entrar al módulo se registra el
/// token de este teléfono para poder recibir los avisos de próxima clase
/// (RF-37) y de sismo (RF-20).
class _EntradaTimbre extends ConsumerWidget {
  const _EntradaTimbre();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rol = ref.watch(authProvider).session?.rol;
    return EnganchePush(
      child: rol == RolUsuario.profesor
          ? const MiHorarioPage()
          : const ControlTimbresPage(),
    );
  }
}
