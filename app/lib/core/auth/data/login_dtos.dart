/// DTOs de la API de autenticación.
///
/// Contrato actual del backend Vapor:
///
/// ```
/// POST /api/auth/login   { "email": "...", "password": "..." }
///   200 -> { "token": "...", "usuario": { "nombre", "email", "rol" } }
///   4xx -> { "error": true, "reason": "..." }
/// ```
///
/// Cuando el backend migre a RS256 (RF-44 a RF-46), el token traerá además los
/// claims `iss`, `aud`, `iat`, `nombre` y `email`. Esta clase no cambia por
/// eso: `usuario` seguirá viniendo en el cuerpo de la respuesta.
library;

class LoginRequest {
  final String email;
  final String password;

  const LoginRequest({required this.email, required this.password});

  Map<String, dynamic> toJson() => {'email': email, 'password': password};
}

class UsuarioDto {
  final String nombre;
  final String email;
  final String rol;

  const UsuarioDto({
    required this.nombre,
    required this.email,
    required this.rol,
  });

  factory UsuarioDto.fromJson(Map<String, dynamic> json) => UsuarioDto(
    nombre: json['nombre'] as String,
    email: json['email'] as String,
    rol: json['rol'] as String,
  );
}

class LoginResponse {
  final String token;
  final UsuarioDto usuario;

  const LoginResponse({required this.token, required this.usuario});

  factory LoginResponse.fromJson(Map<String, dynamic> json) => LoginResponse(
    token: json['token'] as String,
    usuario: UsuarioDto.fromJson(json['usuario'] as Map<String, dynamic>),
  );
}
