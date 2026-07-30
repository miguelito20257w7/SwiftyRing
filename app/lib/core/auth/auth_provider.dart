import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swiftyring/core/auth/data/auth_remote_datasource.dart';
import 'package:swiftyring/core/auth/data/auth_repository_impl.dart';
import 'package:swiftyring/core/auth/data/session_storage.dart';
import 'package:swiftyring/core/auth/domain/auth_exception.dart';
import 'package:swiftyring/core/auth/domain/auth_repository.dart';
import 'package:swiftyring/core/auth/domain/auth_session.dart';
import 'package:swiftyring/core/network/api_client.dart';
import 'package:swiftyring/core/red/servidor.dart';

// ---------------------------------------------------------------------------
// Providers de la aplicación
// ---------------------------------------------------------------------------
// En toda la app hay cuatro: los tres de este archivo más `routerProvider`, en
// `core/router/`. Cada uno existe por una razón concreta que se puede decir en
// una frase.
//
// Antes eran siete. Los otros tres solo envolvían objetos que nadie sustituía,
// y de paso creaban un ciclo —el cliente HTTP necesitaba el token, y quien
// produce el token necesitaba el cliente— que obligaba a un objeto intermedio
// extra solo para romperlo.

/// El cliente HTTP. Es un provider porque **los módulos lo necesitan** para
/// llamar a sus propios endpoints.
///
/// Nace apuntando al servidor vigente. Cuando el administrador lo cambia desde
/// Ajustes de red no se construye otro cliente: `ServidorNotifier` le cambia la
/// dirección a este, para no perder el token de la sesión abierta.
final apiProvider = Provider<ApiClient>(
  (ref) => ApiClient(origen: ref.read(servidorProvider)),
);

/// Dónde se guarda la sesión entre arranques. Es un provider porque **las
/// pruebas lo sustituyen** por una versión en memoria: el almacenamiento real
/// usa el llavero del sistema y en un test no hay plataforma que responda.
final sessionStorageProvider = Provider<SessionStorage>(
  (ref) => SessionStorage(),
);

// ---------------------------------------------------------------------------
// Estado de la sesión
// ---------------------------------------------------------------------------

/// En qué punto del ciclo de vida está la sesión.
///
/// [restaurando] existe para que el router no mande al login a alguien que sí
/// tenía sesión guardada: mientras se lee el almacenamiento seguro se muestra
/// una pantalla de carga, no la bienvenida.
enum EstadoSesion { restaurando, anonimo, autenticado }

class AuthState {
  final EstadoSesion estado;

  /// Sesión activa. Solo es distinta de `null` cuando [estado] es
  /// [EstadoSesion.autenticado].
  final AuthSession? session;

  /// `true` mientras el login está en vuelo (para bloquear el botón).
  final bool enviando;

  /// Mensaje de error listo para pintar, o `null` si no hay error.
  final String? error;

  const AuthState({
    this.estado = EstadoSesion.restaurando,
    this.session,
    this.enviando = false,
    this.error,
  });

  bool get autenticado => estado == EstadoSesion.autenticado;

  AuthState copyWith({
    bool? enviando,
    String? error,
    bool limpiarError = false,
  }) {
    return AuthState(
      estado: estado,
      session: session,
      enviando: enviando ?? this.enviando,
      error: limpiarError ? null : (error ?? this.error),
    );
  }
}

/// Quién está dentro, y las tres acciones que pueden cambiarlo: restaurar,
/// entrar y salir.
class AuthNotifier extends Notifier<AuthState> {
  late final AuthRepository _repositorio;

  @override
  AuthState build() {
    // Las dependencias se arman aquí, a la vista, en vez de repartidas en
    // varios providers. Se lee de arriba abajo y no hay que saltar de archivo
    // en archivo para entender de dónde sale cada pieza.
    _repositorio = AuthRepositoryImpl(
      remoteDatasource: AuthRemoteDatasource(dio: ref.watch(apiProvider).dio),
      storage: ref.watch(sessionStorageProvider),
    );

    // No se puede esperar dentro de `build`, así que la restauración arranca
    // aquí y actualiza el estado cuando termina. El router observa ese cambio.
    Future.microtask(_restaurarSesion);
    return const AuthState();
  }

  Future<void> _restaurarSesion() async {
    try {
      _aplicar(await _repositorio.sesionGuardada());
    } catch (_) {
      // El almacenamiento seguro puede fallar por causas ajenas a la sesión:
      // llavero bloqueado, entitlement de Keychain ausente en macOS, o un
      // plugin que no responde. Sin este catch la excepción se pierde en el
      // microtask y el estado se queda en `restaurando` para siempre: la app
      // arranca en el indicador de carga y no sale de ahí nunca.
      //
      // Ante la duda se entra como anónimo: pedir login otra vez es molesto,
      // quedarse colgado es peor.
      _aplicar(null);
    }
  }

  /// RF-01: pide el token al backend y guarda la sesión.
  Future<void> login({required String email, required String password}) async {
    state = state.copyWith(enviando: true, limpiarError: true);

    try {
      _aplicar(await _repositorio.login(email: email, password: password));
    } on AuthException catch (e) {
      _aplicar(null, error: e.mensaje);
    }
  }

  /// Cierra la sesión de **toda la aplicación**, no solo de un módulo: no
  /// existe una sesión parcial (Contrato de integración, sección 3.5).
  Future<void> cerrarSesion() async {
    await _repositorio.cerrarSesion();
    _aplicar(null);
  }

  /// Punto único donde cambia la sesión. Mantiene sincronizados el estado que
  /// ve la interfaz y el token que usa el cliente HTTP: si esto se hiciera en
  /// cada método por separado, tarde o temprano uno de los dos se olvidaría.
  void _aplicar(AuthSession? sesion, {String? error}) {
    ref.read(apiProvider).usarToken(sesion?.token);
    state = sesion == null
        ? AuthState(estado: EstadoSesion.anonimo, error: error)
        : AuthState(estado: EstadoSesion.autenticado, session: sesion);
  }

  void limpiarError() => state = state.copyWith(limpiarError: true);
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
