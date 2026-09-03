import 'package:dio/dio.dart';
import 'package:swiftyring/core/auth/data/auth_remote_datasource.dart';
import 'package:swiftyring/core/auth/data/session_storage.dart';
import 'package:swiftyring/core/auth/domain/auth_exception.dart';
import 'package:swiftyring/core/auth/domain/auth_repository.dart';
import 'package:swiftyring/core/auth/domain/auth_session.dart';
import 'package:swiftyring/core/auth/domain/rol_usuario.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDatasource remoteDatasource;
  final SessionStorage storage;

  AuthRepositoryImpl({required this.remoteDatasource, required this.storage});

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    try {
      final respuesta = await remoteDatasource.login(
        email: email,
        password: password,
      );

      final rol = RolUsuario.desdeApi(respuesta.usuario.rol);
      if (rol == null) {
        // Pasa si el backend agrega un rol que esta versión de la app no
        // conoce. Mejor decirlo que entrar con permisos indefinidos.
        throw AuthException(
          'Tu cuenta tiene un rol que esta versión de la app no reconoce '
          '(${respuesta.usuario.rol}). Actualiza la aplicación.',
        );
      }

      // El DTO es lo que habla HTTP; la entidad es lo que entiende la app.
      final sesion = AuthSession(
        token: respuesta.token,
        nombre: respuesta.usuario.nombre,
        email: respuesta.usuario.email,
        rol: rol,
      );

      await storage.guardar(sesion);
      await storage.guardarCredenciales(email: email, password: password);
      return sesion;
    } on DioException catch (e) {
      throw AuthException(_mensajeDeRed(e));
    }
  }

  @override
  Future<AuthSession?> sesionGuardada() => storage.leer();

  @override
  Future<AuthSession?> reautenticar() async {
    final creds = await storage.leerCredenciales();
    if (creds == null) return null;

    try {
      return await login(email: creds.email, password: creds.password);
    } on AuthException {
      // Si el servidor rechazó las credenciales (clave cambiada o cuenta suspendida),
      // se borra el almacenamiento seguro para no reintentar en bucle.
      await storage.borrar();
      return null;
    } catch (_) {
      // Si es un fallo de red o conectividad temporal, conservamos las credenciales.
      return null;
    }
  }

  @override
  Future<void> cerrarSesion() => storage.borrar();

  /// Traduce fallos de red a algo que un profesor pueda entender.
  String _mensajeDeRed(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return 'No se pudo conectar con el servidor. Revisa tu conexión.';
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'El servidor tardó demasiado en responder. Intenta de nuevo.';
      default:
        return 'Ocurrió un error inesperado al iniciar sesión.';
    }
  }
}
