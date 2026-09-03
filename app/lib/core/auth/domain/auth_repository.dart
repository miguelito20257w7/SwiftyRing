import 'package:swiftyring/core/auth/domain/auth_session.dart';

abstract class AuthRepository {
  /// RF-01: cambia credenciales por una sesión con token.
  Future<AuthSession> login({required String email, required String password});

  /// Devuelve la sesión guardada en el dispositivo, o `null` si no hay.
  Future<AuthSession?> sesionGuardada();

  /// Intenta renovar la sesión silenciosamente usando las credenciales
  /// guardadas en el almacenamiento seguro.
  Future<AuthSession?> reautenticar();

  /// Borra la sesión y las credenciales guardadas del dispositivo.
  Future<void> cerrarSesion();
}
