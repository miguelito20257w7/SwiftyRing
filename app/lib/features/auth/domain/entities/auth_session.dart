class AuthSession {
  final String token;
  final String nombre;
  final String email;
  final String rol;

  const AuthSession({
    required this.token,
    required this.nombre,
    required this.email,
    required this.rol,
  });
}
