import 'package:dio/dio.dart';

/// Cliente HTTP contra el backend Vapor.
///
/// Todos los endpoints cuelgan de `/api`; cada módulo agrega su prefijo
/// (`/auth`, `/timbres`, `/banos`...). La app recibe el **origen** del servidor
/// (`https://host:puerto`) y le agrega `/api` sola, para que quien lo configura
/// no tenga que saberse ese detalle.
///
/// La dirección ya no está escrita aquí: la elige quien instala el sistema y
/// vive en `core/red/servidor.dart`. Antes estaba fija al computador de
/// desarrollo, así que la app no podía hablar con ningún otro servidor.
///
/// Guarda el token en la cabecera por defecto de Dio. Antes había un objeto
/// aparte (`TokenStore`) y un interceptor que lo leía en cada petición; se
/// quitaron porque solo existían para romper un ciclo entre providers que ya
/// no existe. Con una sola línea se consigue lo mismo y hay dos conceptos
/// menos que entender.
class ApiClient {
  final Dio dio;

  ApiClient({required String origen}) : dio = Dio(_opciones(baseUrlDe(origen)));

  /// Dónde viven los endpoints, a partir del origen del servidor.
  static String baseUrlDe(String origen) => '$origen/api';

  static BaseOptions _opciones(String baseUrl) => BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    contentType: Headers.jsonContentType,
    // Dejamos pasar los 4xx para leer el `reason` que manda Vapor en vez de
    // recibir un DioException pelado y sin cuerpo.
    validateStatus: (status) => status != null && status < 500,
  );

  /// Apunta las peticiones siguientes a otro servidor.
  ///
  /// Se le cambia la dirección al cliente existente en vez de crear uno nuevo:
  /// así el token de la sesión abierta sigue en su sitio y corregir el puerto
  /// no obliga a volver a entrar.
  void usarServidor(String origen) {
    dio.options.baseUrl = baseUrlDe(origen);
  }

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

  /// Comprueba que en esa dirección hay un servidor de SwiftyRing.
  ///
  /// Usa un cliente aparte y con menos paciencia a propósito: se llama para
  /// **probar** una dirección que todavía no se ha guardado, y no debe tocar
  /// al cliente que está sirviendo a la app.
  ///
  /// No basta con recibir un 200. En una red escolar, una dirección mal escrita
  /// puede caer en el router, en una impresora o en el portal cautivo del
  /// proveedor, y todos ésos responden. Por eso se le exige al servidor que se
  /// identifique.
  static Future<ResultadoPrueba> probar(String origen) async {
    final cliente = Dio(
      BaseOptions(
        baseUrl: baseUrlDe(origen),
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 6),
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    try {
      final respuesta = await cliente.get<dynamic>('/salud');
      final datos = respuesta.data;
      if (respuesta.statusCode == 200 &&
          datos is Map &&
          datos['servicio'] == 'swiftyring') {
        return const ResultadoPrueba.exito();
      }
      return const ResultadoPrueba.error(
        'Contestó algo, pero no es un servidor de SwiftyRing. Revisa la dirección.',
      );
    } on DioException catch (e) {
      return ResultadoPrueba.error(switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout => 'El servidor no respondió a tiempo.',
        DioExceptionType.badCertificate =>
          'El certificado del servidor no es válido.',
        _ => 'No se pudo conectar. Revisa la dirección y la red.',
      });
    }
  }
}

/// Cómo salió la prueba de conexión.
class ResultadoPrueba {
  final bool exitoso;
  final String? mensaje;

  const ResultadoPrueba.exito() : exitoso = true, mensaje = null;
  const ResultadoPrueba.error(String this.mensaje) : exitoso = false;
}
