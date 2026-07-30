import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftyring/core/network/api_client.dart';

/// Responde siempre lo mismo, sin salir a la red.
class _AdaptadorFalso implements HttpClientAdapter {
  final int codigo;

  _AdaptadorFalso(this.codigo);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"reason":"Sesión no válida"}',
      codigo,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Qué pasa cuando el servidor rechaza el token.
///
/// El JWT dura 24 horas (RNF-08). Antes nadie atendía ese rechazo y el usuario
/// se quedaba "dentro" viendo errores en cada pantalla, sin manera de saber
/// que solo tenía que volver a entrar.
void main() {
  ApiClient clienteQueResponde(int codigo) {
    final cliente = ApiClient(origen: 'http://127.0.0.1:8080');
    cliente.dio.httpClientAdapter = _AdaptadorFalso(codigo);
    return cliente;
  }

  test('Un 401 en cualquier endpoint avisa que la sesión venció', () async {
    var avisos = 0;
    final cliente = clienteQueResponde(401)..alVencerSesion = () => avisos++;

    await cliente.dio.get<dynamic>('/timbres/hoy');

    expect(avisos, 1);
  });

  test('Un 401 al iniciar sesión NO se toma por sesión vencida', () async {
    // Ahí el 401 significa "esa contraseña no es". Confundirlos anunciaría un
    // error de tecleo como una sesión expirada.
    var avisos = 0;
    final cliente = clienteQueResponde(401)..alVencerSesion = () => avisos++;

    await cliente.dio.post<dynamic>('/auth/login');

    expect(avisos, 0);
  });

  test('Una respuesta normal no avisa nada', () async {
    var avisos = 0;
    final cliente = clienteQueResponde(200)..alVencerSesion = () => avisos++;

    await cliente.dio.get<dynamic>('/timbres/hoy');

    expect(avisos, 0);
  });

  test('Un 403 no es sesión vencida sino falta de permisos', () async {
    // El operador que intenta crear un timbre recibe 403; sacarlo de la app
    // por eso sería absurdo.
    var avisos = 0;
    final cliente = clienteQueResponde(403)..alVencerSesion = () => avisos++;

    await cliente.dio.post<dynamic>('/timbres');

    expect(avisos, 0);
  });

  test('El 401 sigue llegando a quien llamó, para poder leer el motivo', () async {
    // El interceptor avisa, pero no se traga la respuesta: las pantallas
    // muestran el `reason` que manda Vapor.
    final cliente = clienteQueResponde(401);

    final respuesta = await cliente.dio.get<dynamic>('/timbres/hoy');

    expect(respuesta.statusCode, 401);
    expect(respuesta.data['reason'], 'Sesión no válida');
  });
}
