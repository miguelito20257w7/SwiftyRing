import 'package:dio/dio.dart';
import 'package:swiftyring/modules/timbre_escolar/domain/modelos.dart';

/// Error de la API del timbre con un mensaje listo para pintar.
class TimbreApiException implements Exception {
  final String mensaje;

  const TimbreApiException(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Único punto del módulo que habla con los endpoints del Timbre Escolar.
///
/// Mismo patrón que `AuthRemoteDatasource`: el `Dio` compartido ya lleva el
/// token y deja pasar los 4xx, así que aquí se decide si la respuesta es dato
/// o error, y el error sale como [TimbreApiException] con el `reason` de Vapor.
class TimbreApi {
  final Dio dio;

  TimbreApi({required this.dio});

  // ---- Timbres del horario habitual (RF-07..09, F-02) ----

  Future<TimbresHoy> timbresHoy() async =>
      TimbresHoy.fromJson(await _get('/timbres/hoy'));

  Future<List<TimbreHabitual>> listarTimbres() async =>
      (await _getLista('/timbres')).map(TimbreHabitual.fromJson).toList();

  Future<void> guardarTimbre({
    String? id,
    required String etiqueta,
    required String hora,
    required int duracionSeg,
    required bool activo,
    required List<DiaSemana> dias,
  }) async {
    final cuerpo = {
      'etiqueta': etiqueta,
      'hora': hora,
      'duracionSeg': duracionSeg,
      'activo': activo,
      'dias': dias.map((d) => d.name).toList(),
    };
    if (id == null) {
      await _post('/timbres', cuerpo);
    } else {
      await _put('/timbres/$id', cuerpo);
    }
  }

  Future<void> eliminarTimbre(String id) => _delete('/timbres/$id');

  // ---- Horarios especiales (RF-10..13, F-04) ----

  Future<List<HorarioEspecial>> listarEspeciales() async =>
      (await _getLista('/horarios-especiales'))
          .map(HorarioEspecial.fromJson)
          .toList();

  Future<void> guardarEspecial({
    String? id,
    required String nombre,
    required String fechaInicio,
    required String fechaFin,
    required bool activo,
    required List<
      ({String etiqueta, String hora, int duracionSeg, List<DiaSemana> dias})
    >
    timbres,
  }) async {
    final cuerpo = {
      'nombre': nombre,
      'fechaInicio': fechaInicio,
      'fechaFin': fechaFin,
      'activo': activo,
      'timbres': [
        for (final t in timbres)
          {
            'etiqueta': t.etiqueta,
            'hora': t.hora,
            'duracionSeg': t.duracionSeg,
            'dias': t.dias.map((d) => d.name).toList(),
          },
      ],
    };
    if (id == null) {
      await _post('/horarios-especiales', cuerpo);
    } else {
      await _put('/horarios-especiales/$id', cuerpo);
    }
  }

  Future<void> eliminarEspecial(String id) => _delete('/horarios-especiales/$id');

  // ---- Catálogos ----

  Future<List<Materia>> listarMaterias() async =>
      (await _getLista('/materias')).map(Materia.fromJson).toList();

  Future<Materia> crearMateria(String nombre) async =>
      Materia.fromJson(await _post('/materias', {'nombre': nombre}));

  Future<List<Salon>> listarSalones() async =>
      (await _getLista('/salones')).map(Salon.fromJson).toList();

  Future<Salon> crearSalon({required String nombre, String? bloque, int? piso}) async =>
      Salon.fromJson(await _post('/salones', {
        'nombre': nombre,
        if (bloque != null && bloque.isNotEmpty) 'bloque': bloque,
        'piso': ?piso,
      }));

  // ---- Docentes (RF-32, RF-33, F-05) ----

  Future<List<Docente>> listarDocentes() async =>
      (await _getLista('/profesores')).map(Docente.fromJson).toList();

  Future<void> crearDocente({
    required String nombre,
    required String email,
    required String password,
    required Jornada jornada,
    String? directorDeGrupo,
    required List<String> materiaIds,
  }) => _post('/profesores', {
    'nombre': nombre,
    'email': email,
    'password': password,
    'jornada': jornada.name,
    'directorDeGrupo': directorDeGrupo,
    'materiaIds': materiaIds,
  });

  Future<void> editarDocente({
    required String id,
    required String nombre,
    required Jornada jornada,
    String? directorDeGrupo,
    required List<String> materiaIds,
  }) => _put('/profesores/$id', {
    'nombre': nombre,
    'jornada': jornada.name,
    'directorDeGrupo': directorDeGrupo,
    'materiaIds': materiaIds,
  });

  Future<void> suspenderDocente(String id) => _delete('/profesores/$id');

  // ---- Asignación horaria (RF-34, RF-35, F-06) ----

  Future<HorarioSalon> horarioDeSalon(String salonId, DiaSemana dia) async =>
      HorarioSalon.fromJson(await _get('/salones/$salonId/horario/${dia.name}'));

  Future<void> guardarHorarioDeSalon(
    String salonId,
    DiaSemana dia,
    List<
      ({
        int numero,
        String horaInicio,
        String horaFin,
        String materiaId,
        String profesorId,
      })
    >
    bloques,
  ) => _put('/salones/$salonId/horario/${dia.name}', {
    'bloques': [
      for (final b in bloques)
        {
          'numero': b.numero,
          'horaInicio': b.horaInicio,
          'horaFin': b.horaFin,
          'materiaId': b.materiaId,
          'profesorId': b.profesorId,
        },
    ],
  });

  // ---- Vista del profesor (RF-40..42, F-09) ----

  Future<MiHorario> miHorario() async =>
      MiHorario.fromJson(await _get('/mi-horario'));

  // ---- Timbre manual e historial (RF-14..17, RF-23, F-08) ----

  /// RF-16: suena ya, sin mirar el horario. Devuelve a cuántos profesores se
  /// les registró notificación de próxima clase.
  Future<int> timbreManual() async {
    final json = await _post('/timbre/manual', null);
    return json['notificacionesGeneradas'] as int? ?? 0;
  }

  Future<List<Activacion>> listarActivaciones({String? desde, String? hasta}) async =>
      (await _getLista('/activaciones', query: _rango(desde, hasta)))
          .map(Activacion.fromJson)
          .toList();

  Future<List<Sismo>> listarSismos({String? desde, String? hasta}) async =>
      (await _getLista('/sismos', query: _rango(desde, hasta)))
          .map(Sismo.fromJson)
          .toList();

  Future<List<Notificacion>> listarNotificaciones() async =>
      (await _getLista('/notificaciones')).map(Notificacion.fromJson).toList();

  Map<String, String>? _rango(String? desde, String? hasta) {
    final query = {'desde': ?desde, 'hasta': ?hasta};
    return query.isEmpty ? null : query;
  }

  // ---- Configuración (F-07) ----

  Future<Configuracion> configuracion() async =>
      Configuracion.fromJson(await _get('/configuracion'));

  Future<void> guardarConfiguracion({
    String? nombreColegio,
    required double umbralSismicoG,
    required int sismoDuracionMinMs,
  }) => _put('/configuracion', {
    'nombreColegio': nombreColegio,
    'umbralSismicoG': umbralSismicoG,
    'sismoDuracionMinMs': sismoDuracionMinMs,
  });

  // ---- Cuentas (RF-03, dentro de Configuración) ----

  Future<List<UsuarioAdmin>> listarUsuarios() async =>
      (await _getLista('/usuarios')).map(UsuarioAdmin.fromJson).toList();

  Future<void> crearUsuario({
    required String nombre,
    required String email,
    required String password,
    required String rol,
  }) => _post('/usuarios', {
    'nombre': nombre,
    'email': email,
    'password': password,
    'rol': rol,
  });

  Future<void> editarUsuario({
    required String id,
    String? nombre,
    bool? activo,
    String? password,
  }) => _put('/usuarios/$id', {
    'nombre': ?nombre,
    'activo': ?activo,
    'password': ?password,
  });

  Future<void> eliminarUsuario(String id) => _delete('/usuarios/$id');

  // ---- Fontanería HTTP ----

  Future<Map<String, dynamic>> _get(String ruta) async =>
      _mapa(await dio.get<dynamic>(ruta));

  Future<List<Map<String, dynamic>>> _getLista(
    String ruta, {
    Map<String, String>? query,
  }) async {
    final response = await dio.get<dynamic>(ruta, queryParameters: query);
    _verificar(response);
    return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> _post(String ruta, Object? cuerpo) async =>
      _mapa(await dio.post<dynamic>(ruta, data: cuerpo));

  Future<Map<String, dynamic>> _put(String ruta, Object cuerpo) async =>
      _mapa(await dio.put<dynamic>(ruta, data: cuerpo));

  Future<void> _delete(String ruta) async =>
      _verificar(await dio.delete<dynamic>(ruta));

  Map<String, dynamic> _mapa(Response<dynamic> response) {
    _verificar(response);
    final data = response.data;
    // Un 204 no trae cuerpo; quien llame no debe intentar leerlo.
    return data is Map<String, dynamic> ? data : const {};
  }

  void _verificar(Response<dynamic> response) {
    final codigo = response.statusCode ?? 0;
    if (codigo >= 200 && codigo < 300) return;

    final data = response.data;
    if (data is Map && data['reason'] is String) {
      throw TimbreApiException(data['reason'] as String);
    }
    throw TimbreApiException('El servidor respondió con el código $codigo.');
  }
}
