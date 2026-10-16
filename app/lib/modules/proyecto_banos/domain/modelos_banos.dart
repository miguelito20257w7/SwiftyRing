/// Modelos de dominio del módulo Control Baños SS.
///
/// Este archivo NO habla con el backend ni con la base de datos: solo define
/// la "forma" que tiene un dato dentro de la app.
library;

/// Motivo por el que un estudiante sale del aula.
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

  /// Las salidas a enfermería son una excepción de salud: no cuentan para el
  /// límite diario ni ocupan el cupo del grupo. (Supuesto a validar con la
  /// coordinación.)
  bool get exento => this == MotivoSalida.enfermeria;
}

/// Un estudiante del colegio. Por ahora viene de una lista de prueba; cuando
/// exista el backend vendrá de la tabla de estudiantes.
class Estudiante {
  final String id;
  final String nombre;
  final String grado;

  const Estudiante({required this.id, required this.nombre, required this.grado});
}

/// Una salida registrada. Está en curso mientras no tenga `horaRegreso`.
class SalidaBano {
  final String id;
  final String estudianteId;
  final String estudianteNombre;
  final String grado;
  final MotivoSalida motivo;
  final DateTime horaSalida;
  final DateTime? horaRegreso;
  final String? nota;

  const SalidaBano({
    required this.id,
    required this.estudianteId,
    required this.estudianteNombre,
    required this.grado,
    required this.motivo,
    required this.horaSalida,
    this.horaRegreso,
    this.nota,
  });

  bool get enCurso => horaRegreso == null;

  /// Cuánto lleva (o llevó) fuera del aula, en minutos.
  int get duracionMinutos {
    final fin = horaRegreso ?? DateTime.now();
    return fin.difference(horaSalida).inMinutes;
  }

  bool get esDeHoy {
    final a = horaSalida;
    final b = DateTime.now();
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  SalidaBano conRegreso() => SalidaBano(
    id: id,
    estudianteId: estudianteId,
    estudianteNombre: estudianteNombre,
    grado: grado,
    motivo: motivo,
    horaSalida: horaSalida,
    horaRegreso: DateTime.now(),
    nota: nota,
  );
}

/// Un estudiante esperando su turno porque su grupo ya tiene a alguien fuera.
class EsperaSalida {
  final String id;
  final Estudiante estudiante;
  final MotivoSalida motivo;
  final String? nota;
  final DateTime desde;

  const EsperaSalida({
    required this.id,
    required this.estudiante,
    required this.motivo,
    required this.desde,
    this.nota,
  });
}

/// Qué pasó al pedir una salida.
sealed class ResultadoAutorizacion {
  const ResultadoAutorizacion();
}

/// Salió: la salida ya quedó registrada.
class Autorizada extends ResultadoAutorizacion {
  final SalidaBano salida;
  const Autorizada(this.salida);
}

/// El grupo estaba ocupado: quedó en la fila de espera.
class EnEspera extends ResultadoAutorizacion {
  final EsperaSalida espera;
  final int posicion;
  const EnEspera(this.espera, this.posicion);
}

/// No se puede (límite diario, ya está fuera...). `razon` es texto listo para
/// mostrar.
class Rechazada extends ResultadoAutorizacion {
  final String razon;
  const Rechazada(this.razon);
}
