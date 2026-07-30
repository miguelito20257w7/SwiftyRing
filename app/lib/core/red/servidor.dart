import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';

/// A qué servidor le habla la app.
///
/// Antes la dirección estaba escrita en el código, así que la app solo podía
/// funcionar contra el computador del desarrollador. Ahora la escribe quien
/// instala el sistema —cada colegio tiene la suya— y se guarda en el
/// dispositivo.
abstract class Servidor {
  /// La dirección de desarrollo, la que trae la app recién instalada.
  ///
  /// Desde un emulador de Android, `127.0.0.1` es el propio emulador y no el
  /// computador: ahí la dirección especial es `10.0.2.2`.
  static String get porDefecto {
    if (kIsWeb) return 'http://127.0.0.1:8080';
    return defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:8080'
        : 'http://127.0.0.1:8080';
  }

  /// Revisa lo que escribió el usuario y lo deja en forma canónica
  /// (`esquema://host:puerto`, sin barra final y sin ruta).
  ///
  /// Devuelve el error en [error] cuando no sirve, para poder mostrarlo tal
  /// cual debajo del campo.
  static ({String? origen, String? error}) normalizar(String texto) {
    var limpio = texto.trim();
    if (limpio.isEmpty) {
      return (origen: null, error: 'Escribe la dirección del servidor');
    }

    // Sin esquema no se puede saber si es http o https; el más común en una
    // instalación real es el seguro, así que ese se asume.
    if (!limpio.contains('://')) limpio = 'https://$limpio';

    final uri = Uri.tryParse(limpio);
    if (uri == null || uri.host.isEmpty) {
      return (origen: null, error: 'Esa dirección no se entiende');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return (origen: null, error: 'La dirección debe empezar por http:// o https://');
    }

    // Se descarta cualquier ruta: la app sabe que sus endpoints cuelgan de
    // /api y lo agrega sola. Si el usuario pega ".../api", esto lo corrige en
    // vez de terminar pidiendo /api/api/login.
    final puerto = uri.hasPort ? ':${uri.port}' : '';
    return (origen: '${uri.scheme}://${uri.host}$puerto', error: null);
  }

  /// RNF-06 exige HTTPS con certificado válido. La excepción son las
  /// direcciones de la propia red —el computador de desarrollo o un servidor
  /// dentro del colegio—, donde un certificado público no es posible y el
  /// tráfico no sale a internet.
  static bool esInseguro(String origen) {
    final uri = Uri.tryParse(origen);
    if (uri == null || uri.scheme == 'https') return false;
    return !_esRedLocal(uri.host);
  }

  static bool _esRedLocal(String host) {
    if (host == 'localhost' || host.endsWith('.local')) return true;
    final partes = host.split('.');
    if (partes.length != 4) return false;
    final octetos = partes.map(int.tryParse).toList();
    if (octetos.any((o) => o == null)) return false;
    return switch (octetos.cast<int>()) {
      [127, _, _, _] => true,
      [10, _, _, _] => true,
      [192, 168, _, _] => true,
      [172, final segundo, _, _] when segundo >= 16 && segundo <= 31 => true,
      _ => false,
    };
  }
}

/// Guarda la dirección del servidor entre arranques.
///
/// Usa el mismo almacenamiento que la sesión —y no `SharedPreferences`— para
/// no meter dos mecanismos de guardado por un solo dato. La dirección no es un
/// secreto; simplemente viaja por donde ya hay camino.
class AlmacenServidor {
  static const _clave = 'servidor_swiftyring';

  final FlutterSecureStorage _storage;

  AlmacenServidor({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  Future<void> guardar(String origen) =>
      _storage.write(key: _clave, value: origen);

  /// La dirección guardada, o la de desarrollo si no hay ninguna.
  ///
  /// Nunca lanza: el llavero puede fallar por causas ajenas —bloqueado, sin
  /// entitlement en macOS, plugin que no responde— y quedarse sin arrancar por
  /// no poder leer una dirección sería absurdo.
  Future<String> leer() async {
    try {
      return await _storage.read(key: _clave) ?? Servidor.porDefecto;
    } catch (_) {
      return Servidor.porDefecto;
    }
  }
}

/// Dónde se guarda la dirección. Es un provider porque **las pruebas lo
/// sustituyen**: el almacenamiento real necesita plataforma.
final almacenServidorProvider = Provider<AlmacenServidor>(
  (ref) => AlmacenServidor(),
);

/// La dirección con la que arrancó la app.
///
/// `main.dart` la lee del disco **antes** de montar nada y la inyecta aquí. Se
/// hace así, y no cargándola dentro de un provider, para que no exista el
/// instante en que la app ya está viva pero todavía no sabe a quién
/// preguntarle: cualquier petición que cayera en esa ventana iría al servidor
/// equivocado.
final servidorInicialProvider = Provider<String>((ref) => Servidor.porDefecto);

/// La dirección vigente y la única forma de cambiarla.
class ServidorNotifier extends Notifier<String> {
  @override
  String build() => ref.read(servidorInicialProvider);

  /// Guarda la nueva dirección y apunta el cliente HTTP hacia ella.
  ///
  /// Se actualiza el cliente existente en vez de crear uno nuevo: recrearlo
  /// perdería el token de la sesión abierta, y cambiar de servidor no debería
  /// tumbarla si el administrador solo corrigió el puerto.
  Future<void> cambiar(String origen) async {
    await ref.read(almacenServidorProvider).guardar(origen);
    ref.read(apiProvider).usarServidor(origen);
    state = origen;
  }
}

final servidorProvider = NotifierProvider<ServidorNotifier, String>(
  ServidorNotifier.new,
);
