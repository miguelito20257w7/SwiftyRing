/// Roles del sistema, espejo del enum `rol_usuario` de PostgreSQL.
///
/// Este enum es **compartido por toda la aplicación institucional**: el
/// Sistema de Timbre Escolar lo emite en el claim `rol` del JWT y el módulo
/// Control Baños SS lo consume. Cambiarlo requiere acuerdo escrito entre los
/// dos equipos (ver Contrato de integración, sección 6).
enum RolUsuario {
  admin,
  operador,
  profesor;

  /// Traduce el valor que llega del backend. Un rol desconocido no revienta la
  /// app: devuelve `null` y el router lo trata como sesión inválida.
  static RolUsuario? desdeApi(String valor) {
    for (final rol in RolUsuario.values) {
      if (rol.name == valor.toLowerCase()) return rol;
    }
    return null;
  }

  String get etiqueta => switch (this) {
    RolUsuario.admin => 'Administrador',
    RolUsuario.operador => 'Operador',
    RolUsuario.profesor => 'Profesor',
  };

  /// RF-04: solo el administrador gestiona usuarios, horarios y configuración.
  bool get puedeAdministrar => this == RolUsuario.admin;

  /// RF-14 a RF-16: administrador y operador pueden accionar el timbre manual.
  bool get puedeAccionarTimbre =>
      this == RolUsuario.admin || this == RolUsuario.operador;
}
