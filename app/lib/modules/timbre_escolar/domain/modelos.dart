/// Modelos de dominio del módulo Timbre Escolar: espejo de los DTOs que sirve
/// el backend Vapor (`Modules/TimbreEscolar/Controladores`).
///
/// Horas y fechas viajan como texto ISO (`"HH:mm"`, `"yyyy-MM-dd"`), igual que
/// en la base de datos: comparan y ordenan bien como texto, y así la app no
/// arrastra conversiones de zona horaria para datos que no son instantes.
library;

import 'package:swiftyring/core/auth/domain/rol_usuario.dart';

/// Días que soporta el sistema (RF-08). Domingo no existe a propósito.
enum DiaSemana {
  lunes,
  martes,
  miercoles,
  jueves,
  viernes,
  sabado;

  static DiaSemana? desdeApi(String? valor) {
    for (final dia in DiaSemana.values) {
      if (dia.name == valor) return dia;
    }
    return null;
  }

  String get etiqueta => switch (this) {
    DiaSemana.lunes => 'Lunes',
    DiaSemana.martes => 'Martes',
    DiaSemana.miercoles => 'Miércoles',
    DiaSemana.jueves => 'Jueves',
    DiaSemana.viernes => 'Viernes',
    DiaSemana.sabado => 'Sábado',
  };

  /// Inicial para los chips de días del prototipo (L M M J V S).
  String get inicial => switch (this) {
    DiaSemana.lunes => 'L',
    DiaSemana.martes => 'M',
    DiaSemana.miercoles => 'M',
    DiaSemana.jueves => 'J',
    DiaSemana.viernes => 'V',
    DiaSemana.sabado => 'S',
  };
}

enum Jornada {
  manana,
  tarde,
  completa;

  static Jornada desdeApi(String valor) =>
      Jornada.values.firstWhere((j) => j.name == valor, orElse: () => Jornada.completa);

  String get etiqueta => switch (this) {
    Jornada.manana => 'Mañana',
    Jornada.tarde => 'Tarde',
    Jornada.completa => 'Completa',
  };
}

/// Origen de una activación del timbre (RF-17).
enum TipoActivacion {
  automatico,
  manualApp,
  manualFisico,
  sismico;

  static TipoActivacion desdeApi(String valor) => switch (valor) {
    'manual_app' => TipoActivacion.manualApp,
    'manual_fisico' => TipoActivacion.manualFisico,
    'sismico' => TipoActivacion.sismico,
    _ => TipoActivacion.automatico,
  };

  String get etiqueta => switch (this) {
    TipoActivacion.automatico => 'Automático',
    TipoActivacion.manualApp => 'Manual · app',
    TipoActivacion.manualFisico => 'Manual · botón físico',
    TipoActivacion.sismico => 'Sísmico',
  };
}

List<DiaSemana> _dias(dynamic json) => (json as List<dynamic>? ?? [])
    .map((d) => DiaSemana.desdeApi(d as String))
    .whereType<DiaSemana>()
    .toList();

/// Timbre del horario habitual (RF-07..09).
class TimbreHabitual {
  final String id;
  final String etiqueta;
  final String hora;
  final int duracionSeg;
  final bool activo;
  final List<DiaSemana> dias;

  const TimbreHabitual({
    required this.id,
    required this.etiqueta,
    required this.hora,
    required this.duracionSeg,
    required this.activo,
    required this.dias,
  });

  factory TimbreHabitual.fromJson(Map<String, dynamic> json) => TimbreHabitual(
    id: json['id'] as String,
    etiqueta: json['etiqueta'] as String,
    hora: json['hora'] as String,
    duracionSeg: json['duracionSeg'] as int,
    activo: json['activo'] as bool,
    dias: _dias(json['dias']),
  );
}

/// Un toque del día, venga del horario habitual o de uno especial.
class TimbreDelDia {
  final String id;
  final String etiqueta;
  final String hora;
  final int duracionSeg;

  const TimbreDelDia({
    required this.id,
    required this.etiqueta,
    required this.hora,
    required this.duracionSeg,
  });

  factory TimbreDelDia.fromJson(Map<String, dynamic> json) => TimbreDelDia(
    id: json['id'] as String,
    etiqueta: json['etiqueta'] as String,
    hora: json['hora'] as String,
    duracionSeg: json['duracionSeg'] as int,
  );
}

/// Respuesta de `/api/timbres/hoy` (F-02).
class TimbresHoy {
  /// `"habitual"` o `"especial"`.
  final String fuente;
  final String? nombreEspecial;
  final DiaSemana? dia;
  final String horaServidor;
  final List<TimbreDelDia> timbres;
  final TimbreDelDia? proximo;

  const TimbresHoy({
    required this.fuente,
    required this.nombreEspecial,
    required this.dia,
    required this.horaServidor,
    required this.timbres,
    required this.proximo,
  });

  factory TimbresHoy.fromJson(Map<String, dynamic> json) => TimbresHoy(
    fuente: json['fuente'] as String,
    nombreEspecial: json['nombreEspecial'] as String?,
    dia: DiaSemana.desdeApi(json['dia'] as String?),
    horaServidor: json['horaServidor'] as String,
    timbres: (json['timbres'] as List<dynamic>)
        .map((t) => TimbreDelDia.fromJson(t as Map<String, dynamic>))
        .toList(),
    proximo: json['proximo'] == null
        ? null
        : TimbreDelDia.fromJson(json['proximo'] as Map<String, dynamic>),
  );
}

class TimbreEspecialItem {
  final String id;
  final String etiqueta;
  final String hora;
  final int duracionSeg;
  final List<DiaSemana> dias;

  const TimbreEspecialItem({
    required this.id,
    required this.etiqueta,
    required this.hora,
    required this.duracionSeg,
    required this.dias,
  });

  factory TimbreEspecialItem.fromJson(Map<String, dynamic> json) =>
      TimbreEspecialItem(
        id: json['id'] as String,
        etiqueta: json['etiqueta'] as String,
        hora: json['hora'] as String,
        duracionSeg: json['duracionSeg'] as int,
        dias: _dias(json['dias']),
      );
}

/// Horario especial con su vigencia (RF-10..13).
class HorarioEspecial {
  final String id;
  final String nombre;
  final String fechaInicio;
  final String fechaFin;
  final bool activo;

  /// Calculado por el servidor: ¿cubre la fecha de hoy?
  final bool vigente;
  final List<TimbreEspecialItem> timbres;

  const HorarioEspecial({
    required this.id,
    required this.nombre,
    required this.fechaInicio,
    required this.fechaFin,
    required this.activo,
    required this.vigente,
    required this.timbres,
  });

  factory HorarioEspecial.fromJson(Map<String, dynamic> json) => HorarioEspecial(
    id: json['id'] as String,
    nombre: json['nombre'] as String,
    fechaInicio: json['fechaInicio'] as String,
    fechaFin: json['fechaFin'] as String,
    activo: json['activo'] as bool,
    vigente: json['vigente'] as bool,
    timbres: (json['timbres'] as List<dynamic>)
        .map((t) => TimbreEspecialItem.fromJson(t as Map<String, dynamic>))
        .toList(),
  );
}

class Materia {
  final String id;
  final String nombre;

  const Materia({required this.id, required this.nombre});

  factory Materia.fromJson(Map<String, dynamic> json) =>
      Materia(id: json['id'] as String, nombre: json['nombre'] as String);
}

class Salon {
  final String id;
  final String nombre;
  final String? bloque;
  final int? piso;

  const Salon({required this.id, required this.nombre, this.bloque, this.piso});

  factory Salon.fromJson(Map<String, dynamic> json) => Salon(
    id: json['id'] as String,
    nombre: json['nombre'] as String,
    bloque: json['bloque'] as String?,
    piso: json['piso'] as int?,
  );
}

/// Perfil docente completo (RF-32).
class Docente {
  final String id;
  final String nombre;
  final String email;
  final bool activo;
  final Jornada jornada;
  final String? directorDeGrupo;
  final List<Materia> materias;

  const Docente({
    required this.id,
    required this.nombre,
    required this.email,
    required this.activo,
    required this.jornada,
    required this.directorDeGrupo,
    required this.materias,
  });

  factory Docente.fromJson(Map<String, dynamic> json) => Docente(
    id: json['id'] as String,
    nombre: json['nombre'] as String,
    email: json['email'] as String,
    activo: json['activo'] as bool,
    jornada: Jornada.desdeApi(json['jornada'] as String),
    directorDeGrupo: json['directorDeGrupo'] as String?,
    materias: (json['materias'] as List<dynamic>)
        .map((m) => Materia.fromJson(m as Map<String, dynamic>))
        .toList(),
  );
}

/// Bloque del horario de un salón, con nombres resueltos (F-06).
class BloqueAsignado {
  final String id;
  final int numero;
  final String horaInicio;
  final String horaFin;
  final String materiaId;
  final String materiaNombre;
  final String profesorId;
  final String profesorNombre;

  const BloqueAsignado({
    required this.id,
    required this.numero,
    required this.horaInicio,
    required this.horaFin,
    required this.materiaId,
    required this.materiaNombre,
    required this.profesorId,
    required this.profesorNombre,
  });

  factory BloqueAsignado.fromJson(Map<String, dynamic> json) => BloqueAsignado(
    id: json['id'] as String,
    numero: json['numero'] as int,
    horaInicio: json['horaInicio'] as String,
    horaFin: json['horaFin'] as String,
    materiaId: json['materiaId'] as String,
    materiaNombre: json['materiaNombre'] as String,
    profesorId: json['profesorId'] as String,
    profesorNombre: json['profesorNombre'] as String,
  );
}

class HorarioSalon {
  final String salonId;
  final DiaSemana dia;
  final List<BloqueAsignado> bloques;

  const HorarioSalon({
    required this.salonId,
    required this.dia,
    required this.bloques,
  });

  factory HorarioSalon.fromJson(Map<String, dynamic> json) => HorarioSalon(
    salonId: json['salonId'] as String,
    dia: DiaSemana.desdeApi(json['dia'] as String?) ?? DiaSemana.lunes,
    bloques: (json['bloques'] as List<dynamic>)
        .map((b) => BloqueAsignado.fromJson(b as Map<String, dynamic>))
        .toList(),
  );
}

/// Un bloque en la vista del profesor (RF-40).
class MiBloque {
  final int numero;
  final String horaInicio;
  final String horaFin;
  final String materia;
  final String salon;

  const MiBloque({
    required this.numero,
    required this.horaInicio,
    required this.horaFin,
    required this.materia,
    required this.salon,
  });

  factory MiBloque.fromJson(Map<String, dynamic> json) => MiBloque(
    numero: json['numero'] as int,
    horaInicio: json['horaInicio'] as String,
    horaFin: json['horaFin'] as String,
    materia: json['materia'] as String,
    salon: json['salon'] as String,
  );
}

class MiDia {
  final DiaSemana dia;
  final List<MiBloque> bloques;

  const MiDia({required this.dia, required this.bloques});

  factory MiDia.fromJson(Map<String, dynamic> json) => MiDia(
    dia: DiaSemana.desdeApi(json['dia'] as String?) ?? DiaSemana.lunes,
    bloques: (json['bloques'] as List<dynamic>)
        .map((b) => MiBloque.fromJson(b as Map<String, dynamic>))
        .toList(),
  );
}

class MiHorario {
  final DiaSemana? diaActual;
  final String horaServidor;
  final List<MiDia> dias;

  const MiHorario({
    required this.diaActual,
    required this.horaServidor,
    required this.dias,
  });

  factory MiHorario.fromJson(Map<String, dynamic> json) => MiHorario(
    diaActual: DiaSemana.desdeApi(json['diaActual'] as String?),
    horaServidor: json['horaServidor'] as String,
    dias: (json['dias'] as List<dynamic>)
        .map((d) => MiDia.fromJson(d as Map<String, dynamic>))
        .toList(),
  );
}

/// Una entrada de la bitácora de activaciones (RF-17, F-08).
class Activacion {
  final String id;
  final TipoActivacion tipo;
  final DateTime ocurridoAt;
  final String? usuarioNombre;
  final int? duracionSeg;

  const Activacion({
    required this.id,
    required this.tipo,
    required this.ocurridoAt,
    required this.usuarioNombre,
    required this.duracionSeg,
  });

  factory Activacion.fromJson(Map<String, dynamic> json) => Activacion(
    id: json['id'] as String,
    tipo: TipoActivacion.desdeApi(json['tipo'] as String),
    ocurridoAt: DateTime.parse(json['ocurridoAt'] as String).toLocal(),
    usuarioNombre: json['usuarioNombre'] as String?,
    duracionSeg: json['duracionSeg'] as int?,
  );
}

/// Evento sísmico detectado por el módulo físico (RF-23).
class Sismo {
  final String id;
  final double intensidadG;
  final int duracionMs;
  final DateTime ocurridoAt;
  final bool timbreActivado;

  const Sismo({
    required this.id,
    required this.intensidadG,
    required this.duracionMs,
    required this.ocurridoAt,
    required this.timbreActivado,
  });

  factory Sismo.fromJson(Map<String, dynamic> json) => Sismo(
    id: json['id'] as String,
    intensidadG: (json['intensidadG'] as num).toDouble(),
    duracionMs: json['duracionMs'] as int,
    ocurridoAt: DateTime.parse(json['ocurridoAt'] as String).toLocal(),
    timbreActivado: json['timbreActivado'] as bool,
  );
}

/// Notificación de próxima clase registrada (RF-36..38).
class Notificacion {
  final String id;
  final String profesorNombre;
  final String mensaje;
  final bool enviada;
  final DateTime ocurridoAt;

  const Notificacion({
    required this.id,
    required this.profesorNombre,
    required this.mensaje,
    required this.enviada,
    required this.ocurridoAt,
  });

  factory Notificacion.fromJson(Map<String, dynamic> json) => Notificacion(
    id: json['id'] as String,
    profesorNombre: json['profesorNombre'] as String,
    mensaje: json['mensaje'] as String,
    enviada: json['enviada'] as bool,
    ocurridoAt: DateTime.parse(json['ocurridoAt'] as String).toLocal(),
  );
}

/// Parámetros globales del sistema (F-07).
class Configuracion {
  final String? nombreColegio;
  final double umbralSismicoG;
  final int sismoDuracionMinMs;
  final bool modoOffline;

  /// ¿El módulo ESP32 se reportó al servidor hace segundos? Es el latido de
  /// sus consultas de comandos, no un valor guardado.
  final bool moduloEnLinea;

  /// Última vez que el módulo descargó el horario completo.
  final DateTime? ultimaSync;

  const Configuracion({
    required this.nombreColegio,
    required this.umbralSismicoG,
    required this.sismoDuracionMinMs,
    required this.modoOffline,
    required this.moduloEnLinea,
    required this.ultimaSync,
  });

  factory Configuracion.fromJson(Map<String, dynamic> json) => Configuracion(
    nombreColegio: json['nombreColegio'] as String?,
    umbralSismicoG: (json['umbralSismicoG'] as num).toDouble(),
    sismoDuracionMinMs: json['sismoDuracionMinMs'] as int,
    modoOffline: json['modoOffline'] as bool,
    moduloEnLinea: json['moduloEnLinea'] as bool? ?? false,
    ultimaSync: json['ultimaSync'] == null
        ? null
        : DateTime.parse(json['ultimaSync'] as String).toLocal(),
  );
}

/// Cuenta del sistema, vista de administración (RF-03).
class UsuarioAdmin {
  final String id;
  final String nombre;
  final String email;
  final RolUsuario? rol;
  final bool activo;

  /// RF-02: la cuenta principal no se puede suspender ni eliminar.
  final bool esPrincipal;

  const UsuarioAdmin({
    required this.id,
    required this.nombre,
    required this.email,
    required this.rol,
    required this.activo,
    required this.esPrincipal,
  });

  factory UsuarioAdmin.fromJson(Map<String, dynamic> json) => UsuarioAdmin(
    id: json['id'] as String,
    nombre: json['nombre'] as String,
    email: json['email'] as String,
    rol: RolUsuario.desdeApi(json['rol'] as String),
    activo: json['activo'] as bool,
    esPrincipal: json['esPrincipal'] as bool,
  );
}

/// Un dispositivo vinculado del usuario autenticado ("Tus dispositivos
/// vinculados", F-07). El backend solo devuelve los propios.
class DispositivoVinculado {
  final String id;

  /// `ios`, `android` o `web`, como los nombra el backend.
  final String plataforma;
  final String? nombreDispositivo;

  /// Con el token la app reconoce cuál de la lista es *este* dispositivo.
  final String fcmToken;
  final DateTime? registradoAt;
  final DateTime? ultimoUsoAt;

  const DispositivoVinculado({
    required this.id,
    required this.plataforma,
    required this.nombreDispositivo,
    required this.fcmToken,
    required this.registradoAt,
    required this.ultimoUsoAt,
  });

  factory DispositivoVinculado.fromJson(Map<String, dynamic> json) =>
      DispositivoVinculado(
        id: json['id'] as String,
        plataforma: json['plataforma'] as String,
        nombreDispositivo: json['nombreDispositivo'] as String?,
        fcmToken: json['fcmToken'] as String,
        registradoAt: json['registradoAt'] == null
            ? null
            : DateTime.parse(json['registradoAt'] as String).toLocal(),
        ultimoUsoAt: json['ultimoUsoAt'] == null
            ? null
            : DateTime.parse(json['ultimoUsoAt'] as String).toLocal(),
      );
}
