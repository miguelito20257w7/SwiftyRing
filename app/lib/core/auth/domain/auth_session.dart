import 'package:swiftyring/core/auth/domain/rol_usuario.dart';

/// Sesión activa de un usuario.
///
/// Vive en `core/` porque es identidad **de toda la aplicación**, no del
/// módulo de timbre: cualquier módulo puede leerla, ninguno la produce salvo
/// el flujo de login de `core/auth`.
class AuthSession {
  /// JWT firmado por el backend del Timbre Escolar.
  final String token;
  final String nombre;
  final String email;
  final RolUsuario rol;

  const AuthSession({
    required this.token,
    required this.nombre,
    required this.email,
    required this.rol,
  });

  /// Primer nombre, para saludar sin ocupar media pantalla.
  String get primerNombre => nombre.trim().split(' ').first;

  Map<String, String> toJson() => {
    'token': token,
    'nombre': nombre,
    'email': email,
    'rol': rol.name,
  };

  /// Devuelve `null` si el mapa guardado está incompleto o trae un rol que ya
  /// no existe: es preferible pedir login de nuevo a arrancar con basura.
  static AuthSession? fromJson(Map<String, dynamic> json) {
    final token = json['token'];
    final nombre = json['nombre'];
    final email = json['email'];
    final rol = json['rol'];

    if (token is! String || nombre is! String || email is! String) return null;
    if (rol is! String) return null;

    final rolParseado = RolUsuario.desdeApi(rol);
    if (rolParseado == null) return null;

    return AuthSession(
      token: token,
      nombre: nombre,
      email: email,
      rol: rolParseado,
    );
  }
}
