import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:swiftyring/core/auth/domain/rol_usuario.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/ajustes_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/docente_detalle_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/docentes_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/horario_completo_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/mi_horario_page.dart';
import 'package:swiftyring/modules/timbre_escolar/providers.dart';

/// Las pantallas que traducen los frames del prototipo (1:392, 1:527, 1:214)
/// se prueban con datos fijos: aquí importa la estructura, no el backend.

const _materiaLc = Materia(id: 'm1', nombre: 'Lengua Castellana');

const _docente = Docente(
  id: 'p1',
  nombre: 'Luis Monsalve',
  email: 'luis@santasofia.edu.co',
  activo: true,
  jornada: Jornada.manana,
  directorDeGrupo: '11B',
  materias: [_materiaLc],
);

const _horario = MiHorario(
  diaActual: DiaSemana.lunes,
  horaServidor: '08:10',
  dias: [
    MiDia(
      dia: DiaSemana.lunes,
      bloques: [
        MiBloque(
          numero: 1,
          horaInicio: '07:00',
          horaFin: '07:50',
          materia: 'Lengua Castellana',
          salon: '11B',
        ),
        MiBloque(
          numero: 2,
          horaInicio: '07:50',
          horaFin: '08:40',
          materia: 'Ortografía',
          salon: '9D',
        ),
      ],
    ),
    MiDia(
      dia: DiaSemana.martes,
      bloques: [
        MiBloque(
          numero: 1,
          horaInicio: '07:00',
          horaFin: '07:50',
          materia: 'Lengua Castellana',
          salon: '10C',
        ),
      ],
    ),
  ],
);

const _configuracion = Configuracion(
  nombreColegio: 'I.E. Santa Sofía',
  umbralSismicoG: 1.5,
  sismoDuracionMinMs: 1000,
  modoOffline: false,
  moduloEnLinea: true,
  ultimaSync: null,
);

// Riverpod 3 no exporta el tipo `Override`, así que las listas de overrides
// van como `List<Object>` y aquí se les devuelve su tipo real con `cast()`.
Widget _pantalla(Widget hijo, List<Object> overrides) => ProviderScope(
  overrides: overrides.cast(),
  child: MaterialApp(theme: AppTheme.light, home: hijo),
);

void main() {
  group('Detalle de docente (frame 1:392)', () {
    List<Object> overrides() => [
      docentesProvider.overrideWith((ref) async => [_docente]),
      configuracionProvider.overrideWith((ref) async => _configuracion),
      horarioProfesorProvider.overrideWith((ref, id) async => _horario),
    ];

    testWidgets('Muestra el perfil con EDITAR y los datos administrativos', (
      tester,
    ) async {
      await tester.pumpWidget(
        _pantalla(
          const DocenteDetallePage(docenteId: 'p1', inicial: _docente),
          overrides(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Luis Monsalve'), findsOneWidget);
      expect(find.text('Docente de Lengua Castellana'), findsOneWidget);
      expect(find.text('EDITAR'), findsOneWidget);
      // La nota administrativa lleva jornada y dirección de grupo reales.
      expect(find.text('Nota Administrativa'), findsOneWidget);
      expect(
        find.textContaining('director del grupo 11B'),
        findsOneWidget,
      );
      expect(find.text('Estado de Sistema'), findsOneWidget);
    });

    testWidgets('La Distribución Semanal pinta la cuadrícula por siglas', (
      tester,
    ) async {
      await tester.pumpWidget(
        _pantalla(
          const DocenteDetallePage(docenteId: 'p1', inicial: _docente),
          overrides(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Distribución Semanal'), findsOneWidget);
      expect(find.text('JORNADA MAÑANA'), findsOneWidget);
      // Siglas: "Lengua Castellana" → LC (lunes y martes), "Ortografía" → O.
      expect(find.text('LC'), findsNWidgets(2));
      expect(find.text('O'), findsOneWidget);
      expect(find.text('Lunes'), findsOneWidget);
      expect(find.text('Martes'), findsOneWidget);
      expect(find.text('AGREGAR JORNADA'), findsOneWidget);
    });

    testWidgets('Sin clases asignadas lo dice, sin cuadrícula', (tester) async {
      await tester.pumpWidget(
        _pantalla(
          const DocenteDetallePage(docenteId: 'p1', inicial: _docente),
          [
            docentesProvider.overrideWith((ref) async => [_docente]),
            configuracionProvider.overrideWith((ref) async => _configuracion),
            horarioProfesorProvider.overrideWith(
              (ref, id) async => const MiHorario(
                diaActual: DiaSemana.lunes,
                horaServidor: '08:10',
                dias: [],
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('aún no tiene clases asignadas'),
        findsOneWidget,
      );
    });
  });

  group('Gestión de docentes (frame 1:2)', () {
    testWidgets('Tocar un docente abre su detalle', (tester) async {
      final router = GoRouter(
        initialLocation: '/timbre/docentes',
        routes: [
          GoRoute(
            path: '/timbre/docentes',
            builder: (context, state) => const DocentesPage(),
          ),
          GoRoute(
            path: '/timbre/docentes/:id',
            builder: (context, state) => DocenteDetallePage(
              docenteId: state.pathParameters['id']!,
              inicial: state.extra as Docente?,
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            docentesProvider.overrideWith((ref) async => [_docente]),
            configuracionProvider.overrideWith((ref) async => _configuracion),
            horarioProfesorProvider.overrideWith((ref, id) async => _horario),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Luis Monsalve'));
      await tester.pumpAndSettle();

      expect(find.byType(DocenteDetallePage), findsOneWidget);
      expect(find.text('Distribución Semanal'), findsOneWidget);
    });
  });

  group('Vista Profesor (frame 1:527)', () {
    const hoy = TimbresHoy(
      fuente: 'habitual',
      nombreEspecial: null,
      dia: DiaSemana.lunes,
      horaServidor: '09:00',
      timbres: [
        TimbreDelDia(
          id: 't1',
          etiqueta: 'Cambio de clase',
          hora: '09:05',
          duracionSeg: 5,
        ),
      ],
      proximo: TimbreDelDia(
        id: 't1',
        etiqueta: 'Cambio de clase',
        hora: '09:05',
        duracionSeg: 5,
      ),
    );

    testWidgets('El tiempo restante corre segundo a segundo', (tester) async {
      await tester.pumpWidget(
        _pantalla(
          const Scaffold(body: TarjetaProximoTimbre(hoy: hoy)),
          const [],
        ),
      );

      // 09:05 − 09:00 = 5 minutos.
      expect(find.text('TIEMPO RESTANTE'), findsOneWidget);
      expect(find.text('05:00'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('04:59'), findsOneWidget);

      await tester.pump(const Duration(seconds: 59));
      expect(find.text('04:00'), findsOneWidget);

      // Se desmonta para cancelar el temporizador antes de cerrar el test.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('El resumen ofrece "Ver horario completo" y los chips', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/timbre/mi-horario',
        routes: [
          GoRoute(
            path: '/timbre/mi-horario',
            builder: (context, state) => const MiHorarioPage(),
          ),
          GoRoute(
            path: '/timbre/mi-horario/completo',
            builder: (context, state) => const HorarioCompletoPage(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            miHorarioProvider.overrideWith((ref) async => _horario),
            // Pendiente para siempre: sin tarjeta de próximo timbre no hay
            // temporizador y `pumpAndSettle` puede terminar.
            timbresHoyProvider.overrideWith(
              (ref) => Completer<TimbresHoy>().future,
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // El semanal completo ya no se vuelca en la pantalla principal…
      expect(find.text('Ver horario completo'), findsOneWidget);
      expect(find.text('2 Clases hoy'), findsOneWidget);
      expect(find.text('Martes'), findsNothing);

      // …vive detrás del botón (frame 1:527).
      await tester.ensureVisible(find.text('Ver horario completo'));
      await tester.tap(find.text('Ver horario completo'));
      await tester.pumpAndSettle();

      expect(find.byType(HorarioCompletoPage), findsOneWidget);
      expect(find.text('Lunes'), findsOneWidget);
      expect(find.text('Martes'), findsOneWidget);
      expect(find.text('HOY'), findsOneWidget);
    });

    testWidgets('El profesor alterna entre la lista y la cuadrícula', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [miHorarioProvider.overrideWith((ref) async => _horario)],
          child: const MaterialApp(home: HorarioCompletoPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Abre en la lista por día, con los indicadores de la jornada.
      expect(find.text('EN CURSO'), findsOneWidget);
      expect(find.text('Distribución Semanal'), findsNothing);

      await tester.tap(find.text('CUADRÍCULA'));
      await tester.pumpAndSettle();

      // La misma tabla del administrador: siglas de materia por bloque.
      expect(find.text('Distribución Semanal'), findsOneWidget);
      expect(find.text('LC'), findsWidgets);
      expect(find.text('EN CURSO'), findsNothing);

      await tester.tap(find.text('LISTA'));
      await tester.pumpAndSettle();

      expect(find.text('EN CURSO'), findsOneWidget);
    });
  });

  group('Dispositivos vinculados (frame 1:214)', () {
    const admin = UsuarioAdmin(
      id: 'u1',
      nombre: 'Andrea',
      email: 'andrea@santasofia.edu.co',
      rol: RolUsuario.admin,
      activo: true,
      esPrincipal: true,
    );

    List<Object> overrides(List<DispositivoVinculado> dispositivos) => [
      configuracionProvider.overrideWith((ref) async => _configuracion),
      usuariosProvider.overrideWith((ref) async => [admin]),
      dispositivosProvider.overrideWith((ref) async => dispositivos),
    ];

    List<DispositivoVinculado> dosDispositivos() => [
      DispositivoVinculado(
        id: 'd1',
        plataforma: 'ios',
        nombreDispositivo: 'iPhone 15 Pro',
        fcmToken: 'tok-1',
        registradoAt: DateTime.now(),
        ultimoUsoAt: DateTime.now(),
      ),
      DispositivoVinculado(
        id: 'd2',
        plataforma: 'android',
        nombreDispositivo: null,
        fcmToken: 'tok-2',
        registradoAt: DateTime.now(),
        ultimoUsoAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
    ];

    testWidgets('La lista muestra cada dispositivo con su Cerrar sesión', (
      tester,
    ) async {
      await tester.pumpWidget(
        _pantalla(const AjustesPage(), overrides(dosDispositivos())),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('TUS DISPOSITIVOS VINCULADOS'));
      expect(find.text('iPhone 15 Pro'), findsOneWidget);
      // Sin nombre reportado se identifica por su plataforma.
      expect(find.text('Teléfono Android'), findsOneWidget);
      expect(find.textContaining('hace 2 h'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsNWidgets(2));
    });

    testWidgets('Cerrar sesión pide confirmación antes de desvincular', (
      tester,
    ) async {
      await tester.pumpWidget(
        _pantalla(const AjustesPage(), overrides(dosDispositivos())),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Cerrar sesión').first);
      await tester.tap(find.text('Cerrar sesión').first);
      await tester.pumpAndSettle();

      expect(find.text('¿Cerrar sesión de iPhone 15 Pro?'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      // Cancelar no toca nada: los dos siguen vinculados.
      expect(find.text('iPhone 15 Pro'), findsOneWidget);
    });

    testWidgets('Sin dispositivos lo explica en vez de dejar el hueco', (
      tester,
    ) async {
      await tester.pumpWidget(
        _pantalla(const AjustesPage(), overrides(const [])),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('TUS DISPOSITIVOS VINCULADOS'));
      expect(
        find.textContaining('Ningún dispositivo recibe tus notificaciones'),
        findsOneWidget,
      );
    });
  });
}
