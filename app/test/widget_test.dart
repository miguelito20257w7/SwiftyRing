import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/core/auth/data/session_storage.dart';
import 'package:swiftyring/core/auth/domain/auth_session.dart';
import 'package:swiftyring/core/auth/domain/rol_usuario.dart';
import 'package:swiftyring/core/router/app_router.dart';
import 'package:swiftyring/core/shared_widgets/boton_principal.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/main.dart';

/// Almacenamiento en memoria: el real usa Keychain / EncryptedSharedPreferences
/// y en un test no hay plataforma que responda.
class _SessionStorageFalso implements SessionStorage {
  AuthSession? _sesion;

  _SessionStorageFalso([this._sesion]);

  @override
  Future<AuthSession?> leer() async => _sesion;

  @override
  Future<void> guardar(AuthSession sesion) async => _sesion = sesion;

  @override
  Future<void> borrar() async => _sesion = null;
}

/// Monta la app igual que `main.dart`, pero con almacenamiento falso.
Future<void> montarApp(
  WidgetTester tester, {
  AuthSession? sesionGuardada,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionStorageProvider.overrideWithValue(
          _SessionStorageFalso(sesionGuardada),
        ),
        // Se reutiliza la lista real de `main.dart`: si un módulo se agrega o
        // se elimina, las pruebas siguen montando lo mismo que la app.
        routerProvider.overrideWith(
          (ref) => crearRouter(ref, modulos: modulosInstalados),
        ),
      ],
      child: const _AppDePrueba(),
    ),
  );
  // Deja que termine la restauración de sesión y el redirect del router.
  await tester.pumpAndSettle();
}

class _AppDePrueba extends ConsumerWidget {
  const _AppDePrueba();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

void main() {
  testWidgets('Sin sesión guardada se muestra la bienvenida', (tester) async {
    await montarApp(tester);

    expect(find.text('BIENVENIDO'), findsOneWidget);
    expect(find.text('Institucion Educativa Santa Sofia'), findsOneWidget);
    expect(find.text('Iniciar Sesión'), findsOneWidget);
    expect(find.text('Ajustes de red'), findsOneWidget);
  });

  testWidgets('El botón lleva al formulario de inicio de sesión', (
    tester,
  ) async {
    await montarApp(tester);

    await tester.tap(find.text('Iniciar Sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('Un formulario vacío no llama al backend', (tester) async {
    await montarApp(tester);

    await tester.tap(find.text('Iniciar Sesión'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Escribe tu correo'), findsOneWidget);
    expect(find.text('Escribe tu contraseña'), findsOneWidget);
  });

  testWidgets('Con sesión guardada se entra directo al inicio', (tester) async {
    await montarApp(
      tester,
      sesionGuardada: const AuthSession(
        token: 'token-de-prueba',
        nombre: 'Andrea Ramírez',
        email: 'andrea@santasofia.edu.co',
        rol: RolUsuario.admin,
      ),
    );

    expect(find.text('Hola, Andrea'), findsOneWidget);
    expect(find.text('Administrador'), findsOneWidget);
    // La bienvenida ya no debe ser alcanzable con sesión activa.
    expect(find.text('BIENVENIDO'), findsNothing);
  });

  testWidgets('Cerrar sesión devuelve a la bienvenida', (tester) async {
    await montarApp(
      tester,
      sesionGuardada: const AuthSession(
        token: 'token-de-prueba',
        nombre: 'Andrea Ramírez',
        email: 'andrea@santasofia.edu.co',
        rol: RolUsuario.admin,
      ),
    );

    await tester.tap(find.byTooltip('Cerrar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('BIENVENIDO'), findsOneWidget);
  });

  group('Sesión vencida', () {
    testWidgets('El token rechazado devuelve a la bienvenida con el motivo', (
      tester,
    ) async {
      await montarApp(
        tester,
        sesionGuardada: const AuthSession(
          token: 'token-vencido',
          nombre: 'Andrea Ramírez',
          email: 'andrea@santasofia.edu.co',
          rol: RolUsuario.admin,
        ),
      );
      expect(find.text('Hola, Andrea'), findsOneWidget);

      // Lo que haría el interceptor al recibir un 401 del servidor.
      final contenedor = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      contenedor.read(apiProvider).alVencerSesion!();
      await tester.pumpAndSettle();

      expect(find.text('BIENVENIDO'), findsOneWidget);
      expect(find.textContaining('sesión expiró'), findsOneWidget);
    });

    testWidgets('El token deja de mandarse en las peticiones siguientes', (
      tester,
    ) async {
      await montarApp(
        tester,
        sesionGuardada: const AuthSession(
          token: 'token-vencido',
          nombre: 'Andrea Ramírez',
          email: 'andrea@santasofia.edu.co',
          rol: RolUsuario.admin,
        ),
      );

      final contenedor = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      final cliente = contenedor.read(apiProvider);
      expect(cliente.dio.options.headers['Authorization'], isNotNull);

      cliente.alVencerSesion!();
      await tester.pumpAndSettle();

      // Seguir mandando un token muerto solo produce más 401.
      expect(cliente.dio.options.headers['Authorization'], isNull);
    });
  });

  group('Ajustes de red', () {
    testWidgets('El chip de la bienvenida lleva a elegir el servidor', (
      tester,
    ) async {
      // Era decorativo: se dibujaba en el prototipo pero no hacía nada, así
      // que la app solo podía hablar con el computador de desarrollo.
      await montarApp(tester);

      await tester.ensureVisible(find.text('Ajustes de red'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajustes de red'));
      await tester.pumpAndSettle();

      expect(find.text('Servidor'), findsOneWidget);
      expect(find.text('Probar conexión'), findsOneWidget);
    });

    testWidgets('Se llega sin sesión, que es cuando más falta hace', (
      tester,
    ) async {
      // Con la dirección mal puesta el login no falla: no llega a ninguna
      // parte. Si esta pantalla exigiera sesión, no habría forma de salir.
      await montarApp(tester);

      await tester.ensureVisible(find.text('Ajustes de red'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajustes de red'));
      await tester.pumpAndSettle();

      expect(find.text('Servidor'), findsOneWidget);
    });

    testWidgets('Avisa cuando la dirección no va cifrada (RNF-06)', (
      tester,
    ) async {
      await montarApp(tester);
      await tester.ensureVisible(find.text('Ajustes de red'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajustes de red'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'http://colegio.edu.co',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('no va cifrada'), findsOneWidget);
    });

    testWidgets('No avisa por la dirección local de desarrollo', (
      tester,
    ) async {
      await montarApp(tester);
      await tester.ensureVisible(find.text('Ajustes de red'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajustes de red'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'http://127.0.0.1:8080',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('no va cifrada'), findsNothing);
    });
  });

  group('Diseño adaptativo', () {
    // Un desbordamiento de layout lanza excepción en las pruebas, así que
    // "la pantalla se montó sin errores" ya es la mitad de la aserción.
    Future<void> montarEn(
      WidgetTester tester,
      Size tamano, {
      AuthSession? sesion,
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = tamano;
      addTearDown(tester.view.reset);
      await montarApp(tester, sesionGuardada: sesion);
    }

    const telefonoVertical = Size(375, 812);
    const telefonoHorizontal = Size(812, 375);
    const tabletaVertical = Size(834, 1194);
    const escritorio = Size(1440, 900);

    for (final caso in <(String, Size)>[
      ('teléfono vertical', telefonoVertical),
      ('teléfono horizontal', telefonoHorizontal),
      ('tableta vertical', tabletaVertical),
      ('escritorio', escritorio),
    ]) {
      testWidgets('La bienvenida cabe en ${caso.$1}', (tester) async {
        await montarEn(tester, caso.$2);

        expect(find.text('BIENVENIDO'), findsOneWidget);
        expect(find.text('Iniciar Sesión'), findsOneWidget);
        expect(find.text('Ajustes de red'), findsOneWidget);
      });

      testWidgets('El login cabe en ${caso.$1}', (tester) async {
        await montarEn(tester, caso.$2);

        await tester.tap(find.text('Iniciar Sesión'));
        await tester.pumpAndSettle();

        expect(find.text('Correo electrónico'), findsOneWidget);
        expect(find.text('Entrar'), findsOneWidget);
      });

      testWidgets('El lanzador cabe en ${caso.$1}', (tester) async {
        await montarEn(
          tester,
          caso.$2,
          sesion: const AuthSession(
            token: 't',
            nombre: 'Andrea Ramírez',
            email: 'andrea@santasofia.edu.co',
            rol: RolUsuario.admin,
          ),
        );

        expect(find.text('Hola, Andrea'), findsOneWidget);
        expect(find.text('Aplicaciones'), findsOneWidget);
      });
    }

    testWidgets('En horizontal el logo y las acciones van lado a lado', (
      tester,
    ) async {
      await montarEn(tester, telefonoHorizontal);

      final logo = tester.getCenter(find.text('BIENVENIDO'));
      final boton = tester.getCenter(find.byType(BotonPrincipal));

      // Dos columnas: el botón está a la derecha del logo, no debajo.
      expect(
        boton.dx,
        greaterThan(logo.dx),
        reason: 'el botón debería estar en la columna derecha',
      );
      expect(
        (boton.dy - logo.dy).abs(),
        lessThan(telefonoHorizontal.height / 2),
        reason: 'ambos bloques deberían quedar a alturas parecidas',
      );
    });

    testWidgets('En vertical se conserva la disposición del prototipo', (
      tester,
    ) async {
      await montarEn(tester, telefonoVertical);

      final logo = tester.getCenter(find.text('BIENVENIDO'));
      // Se mide el botón, no su texto: la etiqueta va desplazada a la
      // izquierda porque comparte la fila con la flecha.
      final boton = tester.getCenter(find.byType(BotonPrincipal));

      // Una columna: el botón va claramente debajo del logo.
      expect(boton.dy, greaterThan(logo.dy));
      expect((boton.dx - logo.dx).abs(), lessThan(1));
    });

    testWidgets('El contenido no se pega al borde en pantallas anchas', (
      tester,
    ) async {
      await montarEn(tester, escritorio);

      final boton = tester.getRect(find.byType(BotonPrincipal));
      // Centrado, no estirado de borde a borde.
      expect(boton.center.dx, closeTo(escritorio.width / 2, 2));
      expect(boton.width, lessThan(escritorio.width * 0.6));
    });
  });

  group('Lanzador de módulos', () {
    // Estas pruebas se derivan de `modulosInstalados` en vez de nombrar los
    // módulos a mano. Así, al agregar o borrar uno, siguen siendo válidas: si
    // repitieran los nombres, borrar un módulo las rompería por una razón que
    // no es la real.
    AuthSession sesionCon(RolUsuario rol) => AuthSession(
      token: 't',
      nombre: 'Andrea Ramírez',
      email: 'andrea@santasofia.edu.co',
      rol: rol,
    );

    for (final rol in RolUsuario.values) {
      testWidgets('${rol.name} ve solo las apps que le corresponden', (
        tester,
      ) async {
        await montarApp(tester, sesionGuardada: sesionCon(rol));

        for (final modulo in modulosInstalados) {
          expect(
            find.text(modulo.nombre),
            modulo.permiteA(rol) ? findsWidgets : findsNothing,
            reason:
                '${modulo.nombre} debería '
                '${modulo.permiteA(rol) ? "aparecer" : "estar oculto"} '
                'para el rol ${rol.name}',
          );
        }
      });
    }

    testWidgets('Tocar una tarjeta entra al módulo y se puede volver', (
      tester,
    ) async {
      const rol = RolUsuario.admin;
      final visibles = modulosInstalados.where((m) => m.permiteA(rol)).toList();
      expect(visibles, isNotEmpty, reason: 'no hay módulos que probar');

      await montarApp(tester, sesionGuardada: sesionCon(rol));
      expect(find.text('Aplicaciones'), findsOneWidget);

      await tester.tap(find.byKey(Key('modulo-${visibles.first.id}')));
      await tester.pumpAndSettle();

      // Dentro del módulo hay retroceso al lanzador, no cierre de sesión.
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.byTooltip('Cerrar sesión'), findsNothing);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Aplicaciones'), findsOneWidget);
    });

    testWidgets('El cierre de sesión vive en el lanzador', (tester) async {
      await montarApp(tester, sesionGuardada: sesionCon(RolUsuario.admin));

      await tester.tap(find.byTooltip('Cerrar sesión'));
      await tester.pumpAndSettle();

      expect(find.text('BIENVENIDO'), findsOneWidget);
    });
  });

  group('Permisos por rol', () {
    test('El administrador puede administrar y accionar el timbre', () {
      expect(RolUsuario.admin.puedeAdministrar, isTrue);
      expect(RolUsuario.admin.puedeAccionarTimbre, isTrue);
    });

    test('El operador acciona el timbre pero no administra', () {
      expect(RolUsuario.operador.puedeAdministrar, isFalse);
      expect(RolUsuario.operador.puedeAccionarTimbre, isTrue);
    });

    test('El profesor no administra ni acciona el timbre', () {
      expect(RolUsuario.profesor.puedeAdministrar, isFalse);
      expect(RolUsuario.profesor.puedeAccionarTimbre, isFalse);
    });

    test('Un rol desconocido del backend no se interpreta', () {
      expect(RolUsuario.desdeApi('coordinador'), isNull);
      expect(RolUsuario.desdeApi('ADMIN'), RolUsuario.admin);
    });
  });
}
