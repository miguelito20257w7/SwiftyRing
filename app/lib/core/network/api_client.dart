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

  /// Qué hacer cuando el servidor dice que el token ya no vale.
  ///
  /// Lo pone `AuthNotifier`, igual que el token: el cliente HTTP avisa, pero no
  /// sabe qué es una sesión ni cómo cerrarla. Si en vez de este gancho el
  /// cliente leyera el provider de sesión, el grafo se cerraría sobre sí mismo
  /// —quien produce el token necesita al cliente— que es justo el ciclo que
  /// costó un objeto intermedio en su día.
  void Function()? alVencerSesion;

  ApiClient({required String origen}) : dio = Dio(_opciones(baseUrlDe(origen))) {
    dio.interceptors.add(
      InterceptorsWrapper(
        // El 401 llega por aquí y no por `onError` porque `validateStatus`
        // deja pasar las respuestas del servidor para poder leer el `reason`
        // de Vapor.
        onResponse: (respuesta, handler) {
          if (respuesta.statusCode == 401 &&
              !_esInicioDeSesion(respuesta.requestOptions.path)) {
            alVencerSesion?.call();
          }
          handler.next(respuesta);
        },
      ),
    );
  }

  /// En el login, un 401 significa "esa contraseña no es" y no "tu sesión
  /// venció". Confundirlos haría que un error de tecleo se anunciara como una
  /// sesión expirada.
  static bool _esInicioDeSesion(String ruta) => ruta.endsWith('/auth/login');

  /// Dónde viven los endpoints, a partir del origen del servidor.
  static String baseUrlDe(String origen) => '$origen/api';

  static BaseOptions _opciones(String baseUrl) => BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    // Los tres plazos son fases distintas y hacen falta los tres. `connect`
    // cubre abrir la conexión y `receive` cubre esperar la respuesta, pero
    // entre medio está el envío del cuerpo, y ése es el que faltaba: si la
    // conexión se muere justo ahí —una red escolar que se cae, una conexión
    // reutilizada que el proxy ya había cerrado— Dio se queda esperando **para
    // siempre**, porque `receive` no aplica a una respuesta que nunca empezó.
    //
    // Se vio guardando el horario de un salón: la app girando sin fin y el
    // servidor anotando «stream ended at an unexpected time». Sin este plazo el
    // usuario no recibe ni un error que le diga que reintente.
    sendTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    contentType: Headers.jsonContentType,
    // Dejamos pasar **todas** las respuestas del servidor —4xx y 5xx— para
    // leer el `reason` que manda Vapor en vez de recibir un DioException
    // pelado y sin cuerpo. Quien llama decide si el código es dato o error.
    //
    // Los 5xx también entran aquí a propósito: cuando el backend falla suele
    // explicar por qué, y ese texto sirve más que un "código 500" a secas. Lo
    // que sigue lanzando DioException es lo que ni llega a ser respuesta
    // (servidor apagado, sin red, timeout), y de eso se encarga el guard de
    // cada módulo.
    validateStatus: (status) => status != null && status < 600,
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
        validateStatus: (status) => status != null && status < 600,
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
      // Un 5xx sí es un servidor, pero uno que está mal. Mandar a revisar la
      // dirección en ese caso pondría a buscar el error donde no está.
      if ((respuesta.statusCode ?? 0) >= 500) {
        return ResultadoPrueba.error(
          'Hay un servidor en esa dirección, pero respondió con un error '
          '(código ${respuesta.statusCode}). Revisa que esté bien arrancado.',
        );
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
