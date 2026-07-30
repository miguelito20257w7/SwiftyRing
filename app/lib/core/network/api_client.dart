import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Cliente HTTP contra el backend Vapor.
///
/// Todos los endpoints cuelgan de `/api`; cada módulo agrega su prefijo
/// (`/auth`, `/horarios`, `/banos`...).
///
/// Guarda el token en la cabecera por defecto de Dio. Antes había un objeto
/// aparte (`TokenStore`) y un interceptor que lo leía en cada petición; se
/// quitaron porque solo existían para romper un ciclo entre providers que ya
/// no existe. Con una sola línea se consigue lo mismo y hay dos conceptos
/// menos que entender.
class ApiClient {
  final Dio dio;

  ApiClient() : dio = Dio(_opciones());

  /// El backend corre en la máquina de desarrollo. Desde un emulador de
  /// Android, `127.0.0.1` es el propio emulador y no el Mac: ahí hay que usar
  /// la dirección especial `10.0.2.2`. En web, macOS e iOS el localhost sirve.
  static String get _host {
    if (kIsWeb) return '127.0.0.1';
    return defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : '127.0.0.1';
  }

  /// TODO: cuando el backend esté en el servidor real, esto pasa a
  /// `https://api.swiftydevs.dev/api` (RNF-06: HTTPS obligatorio).
  static String get baseUrl => 'http://$_host:8080/api';

  static BaseOptions _opciones() => BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    contentType: Headers.jsonContentType,
    // Dejamos pasar los 4xx para leer el `reason` que manda Vapor en vez de
    // recibir un DioException pelado y sin cuerpo.
    validateStatus: (status) => status != null && status < 500,
  );

  /// Adjunta (o quita) el JWT en todas las peticiones siguientes.
  ///
  /// Lo llama `AuthNotifier` cada vez que cambia la sesión, que es el único
  /// sitio donde el token puede cambiar.
  void usarToken(String? token) {
    if (token == null) {
      dio.options.headers.remove('Authorization');
    } else {
      dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }
}
