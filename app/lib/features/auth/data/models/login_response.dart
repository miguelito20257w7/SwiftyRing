class UsuarioDto {
  final String nombre;
  final String email;
  final String rol;

  const UsuarioDto({required this.nombre, required this.email, required this.rol});

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
