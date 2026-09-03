import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/core/auth/data/session_storage.dart';
import 'package:swiftyring/core/auth/domain/auth_session.dart';
import 'package:swiftyring/core/auth/domain/rol_usuario.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/modules/timbre_escolar/data/timbre_api.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/ajustes_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/asignacion_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/ajustes_profesor_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/docente_detalle_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/docentes_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/horario_completo_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/pages/mi_horario_page.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/timbre_ui.dart';
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
      expect(find.text('HOY LUNES'), findsOneWidget);
    });

    testWidgets('El profesor alterna entre la cuadrícula y la lista', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [miHorarioProvider.overrideWith((ref) async => _horario)],
          child: const MaterialApp(home: HorarioCompletoPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Abre en la cuadrícula: la semana entera de un vistazo, con las siglas
      // de materia por bloque.
      expect(find.text('Distribución Semanal'), findsOneWidget);
      expect(find.text('LC'), findsWidgets);
      expect(find.text('EN CURSO'), findsNothing);

      await tester.tap(find.text('LISTA'));
      await tester.pumpAndSettle();

      // La lista por día trae los indicadores de la jornada.
      expect(find.text('EN CURSO'), findsOneWidget);
      expect(find.text('Distribución Semanal'), findsNothing);

      await tester.tap(find.text('CUADRÍCULA'));
      await tester.pumpAndSettle();

      expect(find.text('Distribución Semanal'), findsOneWidget);
    });

    testWidgets('En la cuadrícula solo la clase en curso va en amarillo fuerte', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [miHorarioProvider.overrideWith((ref) async => _horario)],
          child: const MaterialApp(home: HorarioCompletoPage()),
        ),
      );
      await tester.pumpAndSettle();

      // El fixture tiene tres bloques —dos el lunes (hoy) y uno el martes— y
      // la hora del servidor, 08:10, cae dentro del segundo del lunes.
      // Antes se encendía el día entero; ahora es una sola celda.
      final fuertes = tester
          .widgetList<Container>(find.byType(Container))
          .where((contenedor) {
            final decoracion = contenedor.decoration;
            return decoracion is BoxDecoration &&
                decoracion.color ==
                    TimbreColors.amarillo.withValues(alpha: 0.9);
          });

      expect(fuertes.length, 1);
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

  group('Asignación horaria por docente (F-06)', () {
    const salones = [
      Salon(id: 's1', nombre: '11B'),
      Salon(id: 's2', nombre: '9D'),
    ];

    Future<_ApiFalsa> montar(WidgetTester tester) async {
      final api = _ApiFalsa(
        bloques: const [
          BloqueDocente(
            id: 'b1',
            horaInicio: '07:00',
            horaFin: '07:50',
            materiaId: 'm1',
            materiaNombre: 'Lengua Castellana',
            salonId: 's1',
            salonNombre: '11B',
          ),
          BloqueDocente(
            id: 'b2',
            horaInicio: '07:50',
            horaFin: '08:40',
            materiaId: 'm1',
            materiaNombre: 'Lengua Castellana',
            salonId: 's2',
            salonNombre: '9D',
          ),
        ],
      );

      await tester.pumpWidget(
        _pantalla(const AsignacionPage(), [
          timbreApiProvider.overrideWithValue(api),
          docentesProvider.overrideWith((ref) async => [_docente]),
          materiasProvider.overrideWith((ref) async => [_materiaLc]),
          salonesProvider.overrideWith((ref) async => salones),
        ]),
      );
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('Ofrece los dos modos y abre en el de salón', (tester) async {
      await montar(tester);

      expect(find.text('POR SALÓN'), findsOneWidget);
      expect(find.text('POR DOCENTE'), findsOneWidget);
      // El modo por salón es el de F-06 y sigue siendo el de entrada.
      expect(find.text('Selecciona un salón'), findsOneWidget);
    });

    testWidgets('Por docente, cada bloque muestra su salón', (tester) async {
      await montar(tester);

      await tester.tap(find.text('POR DOCENTE'));
      await tester.pumpAndSettle();

      expect(find.text('Selecciona un docente'), findsOneWidget);

      // Se toca el desplegable por su tipo: el texto de pista vive dentro de
      // la decoración del campo y tocarlo no siempre acierta al control.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Luis Monsalve').last);
      await tester.pumpAndSettle();

      // La jornada del docente puede estar repartida entre varios salones, y
      // es justamente lo que este modo deja ver de una vez.
      expect(find.text('Luis Monsalve · Lunes'), findsOneWidget);
      expect(find.text('2 BLOQUES'), findsOneWidget);
      expect(find.text('11B'), findsOneWidget);
      expect(find.text('9D'), findsOneWidget);
    });

    testWidgets('Guardar manda los bloques con su salón', (tester) async {
      final api = await montar(tester);

      await tester.tap(find.text('POR DOCENTE'));
      await tester.pumpAndSettle();
      // Se toca el desplegable por su tipo: el texto de pista vive dentro de
      // la decoración del campo y tocarlo no siempre acierta al control.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Luis Monsalve').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Guardar horario'));
      await tester.tap(find.text('Guardar horario'));
      await tester.pumpAndSettle();

      expect(api.guardado, isNotNull);
      expect(api.guardado!.length, 2);
      // El salón viaja por bloque; el docente va en la ruta, no en el cuerpo.
      expect(api.guardado!.map((b) => b.salonId), ['s1', 's2']);
    });
  });

  group('Ajustes del profesor (F-09)', () {
    const profesor = AuthSession(
      token: 'jwt-de-prueba',
      nombre: 'Luis Monsalve',
      email: 'luis@santasofia.edu.co',
      rol: RolUsuario.profesor,
    );

    const resumen = ResumenSistema(
      nombreColegio: 'I.E. Santa Sofía',
      moduloEnLinea: true,
      ultimaSync: null,
    );

    List<Object> overrides({
      ResumenSistema conResumen = resumen,
      List<DispositivoVinculado> dispositivos = const [],
    }) => [
      // La tarjeta de perfil sale de la sesión, así que hay que restaurarla:
      // el almacenamiento real es Keychain y en un test no hay plataforma.
      sessionStorageProvider.overrideWithValue(_AlmacenFalso(profesor)),
      resumenSistemaProvider.overrideWith((ref) async => conResumen),
      dispositivosProvider.overrideWith((ref) async => dispositivos),
    ];

    testWidgets('Muestra quién eres, el colegio y el estado del módulo', (
      tester,
    ) async {
      await tester.pumpWidget(
        _pantalla(const AjustesProfesorPage(), overrides()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Luis Monsalve'), findsOneWidget);
      expect(find.text('luis@santasofia.edu.co'), findsOneWidget);
      expect(find.text('Profesor'), findsOneWidget);
      expect(find.text('I.E. Santa Sofía'), findsOneWidget);
      expect(find.text('Módulo ESP32-WROOM'), findsOneWidget);
      expect(find.text('● ONLINE'), findsOneWidget);
    });

    testWidgets('No expone nada de administración', (tester) async {
      await tester.pumpWidget(
        _pantalla(const AjustesProfesorPage(), overrides()),
      );
      await tester.pumpAndSettle();

      // Las cuentas del sistema y la calibración sísmica son del admin: aquí
      // ni se piden al backend (respondería 403) ni se pintan.
      expect(find.text('Usuarios y Dispositivos'), findsNothing);
      expect(find.textContaining('UMBRAL SÍSMICO'), findsNothing);
      expect(find.text('Guardar configuración'), findsNothing);
      // El nombre del colegio se lee, no se edita.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('Lista sus dispositivos vinculados', (tester) async {
      await tester.pumpWidget(
        _pantalla(
          const AjustesProfesorPage(),
          overrides(
            dispositivos: [
              DispositivoVinculado(
                id: 'd1',
                plataforma: 'ios',
                nombreDispositivo: 'iPhone de Luis',
                fcmToken: 'tok-1',
                registradoAt: DateTime.now(),
                ultimoUsoAt: DateTime.now(),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('TUS DISPOSITIVOS VINCULADOS'));
      expect(find.text('iPhone de Luis'), findsOneWidget);
      // Desvincular el propio teléfono sí es del dueño, no del administrador.
      expect(find.text('Cerrar sesión'), findsOneWidget);
    });

    testWidgets('Sin nombre de colegio configurado lo dice', (tester) async {
      await tester.pumpWidget(
        _pantalla(
          const AjustesProfesorPage(),
          overrides(
            conResumen: const ResumenSistema(
              nombreColegio: null,
              moduloEnLinea: false,
              ultimaSync: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sin nombre configurado'), findsOneWidget);
      expect(find.text('● OFFLINE'), findsOneWidget);
    });
  });
}

/// Solo se sobrescribe lo que la pantalla de asignación llama; el resto de
/// [TimbreApi] queda como está y nunca se ejecuta porque no hay red detrás.
class _ApiFalsa extends TimbreApi {
  _ApiFalsa({required this.bloques}) : super(dio: Dio());

  final List<BloqueDocente> bloques;

  /// Lo último que se mandó a guardar, para comprobar qué se envió.
  List<({String horaInicio, String horaFin, String materiaId, String salonId})>?
  guardado;

  @override
  Future<HorarioDocenteDia> horarioDeProfesorEnDia(
    String profesorId,
    DiaSemana dia,
  ) async =>
      HorarioDocenteDia(profesorId: profesorId, dia: dia, bloques: bloques);

  @override
  Future<void> guardarHorarioDeProfesor(
    String profesorId,
    DiaSemana dia,
    List<
      ({String horaInicio, String horaFin, String materiaId, String salonId})
    >
    bloques,
  ) async {
    guardado = bloques;
  }
}

/// Almacenamiento de sesión en memoria: el real usa Keychain y en un test no
/// hay plataforma que responda.
class _AlmacenFalso implements SessionStorage {
  AuthSession? _sesion;
  ({String email, String password})? _credenciales;

  _AlmacenFalso([this._sesion]);

  @override
  Future<AuthSession?> leer() async => _sesion;

  @override
  Future<void> guardar(AuthSession sesion) async => _sesion = sesion;

  @override
  Future<void> guardarCredenciales({
    required String email,
    required String password,
  }) async => _credenciales = (email: email, password: password);

  @override
  Future<({String email, String password})?> leerCredenciales() async =>
      _credenciales;

  @override
  Future<void> borrar() async {
    _sesion = null;
    _credenciales = null;
  }
}
