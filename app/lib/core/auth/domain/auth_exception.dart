/// Error de autenticación listo para mostrarse al usuario.
///
/// La capa de presentación nunca ve un `DioException` ni un código HTTP: solo
/// un mensaje en español que puede pintar en pantalla.
class AuthException implements Exception {
  final String mensaje;

  const AuthException(this.mensaje);

  @override
  String toString() => mensaje;
}
