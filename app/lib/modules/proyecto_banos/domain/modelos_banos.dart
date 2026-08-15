/// Modelos de dominio del módulo Control Baños SS.
///
/// Este archivo NO habla con el backend ni con la base de datos: solo define
/// la "forma" que tiene un dato dentro de la app. Es el equivalente a las
/// tarjetas de tu prototipo, pero escrito como código.
library;

/// Motivo por el que un estudiante sale del aula (pantalla "Autorizar salida"
/// de tu prototipo: Baño / Enfermería / Agua / Otro).
enum MotivoSalida {
  bano,
  enfermeria,
  agua,
  otro;

  String get etiqueta => switch (this) {
    MotivoSalida.bano => 'Baño',
    MotivoSalida.enfermeria => 'Enfermería',
    MotivoSalida.agua => 'Agua',
    MotivoSalida.otro => 'Otro',
  };
}

/// Una salida registrada. Puede estar en curso (sin `horaRegreso`) o ya
/// completada (con `horaRegreso`).
///
/// Los campos son deliberadamente simples (String para nombre, DateTime para
/// horas): es la versión mínima para poder construir las pantallas. Más
/// adelante, cuando conectemos con el backend real, es probable que el
/// `id` deje de ser un número inventado y pase a venir del servidor — eso no
/// obliga a cambiar nada más.
class SalidaBano {
  final String id;
  final String estudianteNombre;
  final String grado;
  final MotivoSalida motivo;
  final DateTime horaSalida;
  final DateTime? horaRegreso;
  final String? nota;

  const SalidaBano({
    required this.id,
    required this.estudianteNombre,
    required this.grado,
    required this.motivo,
    required this.horaSalida,
    this.horaRegreso,
    this.nota,
  });

  /// true mientras el estudiante sigue fuera del aula.
  bool get enCurso => horaRegreso == null;

  /// Cuánto lleva (o llevó) fuera del aula, en minutos.
  int get duracionMinutos {
    final fin = horaRegreso ?? DateTime.now();
    return fin.difference(horaSalida).inMinutes;
  }

  /// Copia la salida con el regreso ya registrado "ahora".
  SalidaBano conRegreso() => SalidaBano(
    id: id,
    estudianteNombre: estudianteNombre,
    grado: grado,
    motivo: motivo,
    horaSalida: horaSalida,
    horaRegreso: DateTime.now(),
    nota: nota,
  );
}
