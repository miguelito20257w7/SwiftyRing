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

  /// El mismo horario armado desde el docente: sus clases de un día, en los
  /// salones que sean.
  Future<HorarioDocenteDia> horarioDeProfesorEnDia(
    String profesorId,
    DiaSemana dia,
  ) async => HorarioDocenteDia.fromJson(
    await _get('/profesores/$profesorId/horario/${dia.name}'),
  );

  /// Reemplaza las clases de ese docente en ese día. El servidor solo toca los
  /// bloques de este profesor: los de sus compañeros en los mismos salones
  /// quedan como estaban.
  Future<void> guardarHorarioDeProfesor(
    String profesorId,
    DiaSemana dia,
    List<
      ({String horaInicio, String horaFin, String materiaId, String salonId})
    >
    bloques,
  ) => _put('/profesores/$profesorId/horario/${dia.name}', {
    'bloques': [
      for (final b in bloques)
        {
          'horaInicio': b.horaInicio,
          'horaFin': b.horaFin,
          'materiaId': b.materiaId,
          'salonId': b.salonId,
        },
    ],
  });

  // ---- Dispositivos y push (RF-32, RF-37) ----

  /// Registra (o refresca) el token FCM de este teléfono para que el backend
  /// sepa a dónde mandarle los avisos de próxima clase. Es idempotente: si el
  /// token ya existía, el servidor actualiza el dueño y el último uso en vez
  /// de duplicarlo.
  Future<void> registrarDispositivo({
    required String plataforma,
    required String fcmToken,
    String? nombreDispositivo,
  }) => _post('/dispositivos', {
    'plataforma': plataforma,
    'fcmToken': fcmToken,
    'nombreDispositivo': ?nombreDispositivo,
  });

  /// "Tus dispositivos vinculados" (F-07): el backend responde solo los del
  /// usuario autenticado.
  Future<List<DispositivoVinculado>> listarDispositivos() async =>
      (await _getLista('/dispositivos'))
          .map(DispositivoVinculado.fromJson)
          .toList();

  /// El "Cerrar sesión" de un dispositivo: se borra el registro y ese
  /// teléfono deja de recibir avisos.
  Future<void> desvincularDispositivo(String id) => _delete('/dispositivos/$id');

  /// Envía la orden de restablecimiento de fábrica al módulo físico ESP32
  Future<void> restablecerModuloFisico() async => _post('/dispositivo/reset', {});

  /// Genera un código de autorización temporal para vincular el módulo físico ESP32
  Future<Map<String, dynamic>> solicitarCodigoSetup() async {
    return _post('/dispositivo/setup-code', {});
  }

  /// Obtiene la clave de aprovisionamiento (DEVICE_API_KEY) configurada en el servidor (solo admin)
  Future<Map<String, String>> obtenerClaveAprovisionamiento() async {
    final mapa = await _get('/dispositivo/provision-key');
    return {
      'deviceApiKey': (mapa['deviceApiKey'] ?? mapa['device_api_key'] ?? '').toString(),
      'apiBase': (mapa['apiBase'] ?? mapa['api_base'] ?? '').toString(),
    };
  }

  // ---- Vista del profesor (RF-40..42, F-09) ----

  Future<MiHorario> miHorario() async =>
      MiHorario.fromJson(await _get('/mi-horario'));

  /// La distribución semanal de un docente concreto, para su vista de detalle
  /// en Gestión de Docentes (solo administrador). Misma forma que
  /// [miHorario]: las dos pantallas pintan el mismo modelo.
  Future<MiHorario> horarioDeProfesor(String id) async =>
      MiHorario.fromJson(await _get('/profesores/$id/horario'));

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

  /// F-09: la parte de la configuración que no es de administración. El
  /// endpoint completo responde 403 a quien no sea admin, así que la pantalla
  /// de ajustes del profesor pregunta por aquí.
  Future<ResumenSistema> resumenSistema() async =>
      ResumenSistema.fromJson(await _get('/configuracion/resumen'));

  Future<void> guardarConfiguracion({
    String? nombreColegio,
    required double umbralSismicoG,
    required int sismoDuracionMinMs,
    bool? modoUps,
    int? duracionTimbreManualSeg,
  }) => _put('/configuracion', {
    'nombreColegio': nombreColegio,
    'umbralSismicoG': umbralSismicoG,
    'sismoDuracionMinMs': sismoDuracionMinMs,
    'modoUps': ?modoUps,
    'duracionTimbreManualSeg': ?duracionTimbreManualSeg,
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
      _mapa(await _pedir(() => dio.get<dynamic>(ruta)));

  Future<List<Map<String, dynamic>>> _getLista(
    String ruta, {
    Map<String, String>? query,
  }) async {
    final response = await _pedir(
      () => dio.get<dynamic>(ruta, queryParameters: query),
    );
    _verificar(response);
    return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> _post(String ruta, Object? cuerpo) async =>
      _mapa(await _pedir(() => dio.post<dynamic>(ruta, data: cuerpo)));

  Future<Map<String, dynamic>> _put(String ruta, Object cuerpo) async =>
      _mapa(await _pedir(() => dio.put<dynamic>(ruta, data: cuerpo)));

  Future<void> _delete(String ruta) async =>
      _verificar(await _pedir(() => dio.delete<dynamic>(ruta)));

  /// Por aquí pasan **todas** las peticiones del módulo.
  ///
  /// Un fallo que no llega a ser respuesta —servidor apagado, sin red, la
  /// dirección de Ajustes mal escrita, el servidor que no contesta a tiempo—
  /// sale de Dio como `DioException`, y ése no lo atrapa nadie: las pantallas
  /// solo saben esperar [TimbreApiException]. Sin esta traducción, guardar un
  /// docente con el backend caído revienta el botón, y una lista fallida pinta
  /// el texto en inglés de Dio en la cara del profesor.
  Future<Response<dynamic>> _pedir(
    Future<Response<dynamic>> Function() peticion,
  ) async {
    try {
      return await peticion();
    } on DioException catch (e) {
      throw TimbreApiException(_mensajeDeRed(e));
    }
  }

  /// Traduce el fallo de red a algo que un profesor pueda leer y actuar.
  String _mensajeDeRed(DioException e) => switch (e.type) {
    DioExceptionType.connectionError =>
      'No se pudo conectar con el servidor. Revisa la red o la dirección '
          'del servidor en Ajustes.',
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout =>
      'El servidor tardó demasiado en responder. Intenta de nuevo.',
    DioExceptionType.badCertificate =>
      'El certificado del servidor no es válido.',
    DioExceptionType.cancel => 'La petición se canceló.',
    // Con `validateStatus` dejando pasar hasta el 599, una respuesta del
    // servidor ya no llega por aquí: la resuelve `_verificar`. Queda por si
    // algún día cambia esa regla.
    _ => 'Ocurrió un error inesperado al hablar con el servidor.',
  };

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
    final razon = data is Map && data['reason'] is String
        ? data['reason'] as String
        : null;

    // Un 5xx no es culpa de quien está usando la app: no hay nada que
    // corregir en el formulario, así que lo primero que se dice es a quién
    // avisar. El detalle del servidor va detrás, porque a veces es el
    // "Something went wrong" genérico de Vapor y no le sirve a nadie.
    if (codigo >= 500) {
      throw TimbreApiException(
        'El servidor tuvo un problema (código $codigo). '
        'Vuelve a intentarlo; si sigue igual, avisa al administrador.'
        '${razon == null ? '' : '\n$razon'}',
      );
    }

    if (razon != null) throw TimbreApiException(razon);
    throw TimbreApiException('El servidor respondió con el código $codigo.');
  }
}
