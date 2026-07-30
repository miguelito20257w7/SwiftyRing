import 'package:flutter_test/flutter_test.dart';
import 'package:swiftyring/core/network/api_client.dart';
import 'package:swiftyring/core/red/servidor.dart';

/// Pruebas de la dirección del servidor.
///
/// Es lógica pura y es la que decide a dónde va **toda** la app: si normaliza
/// mal, ninguna pantalla funciona y el error se ve lejos de aquí.
void main() {
  group('Normalizar la dirección', () {
    test('Sin esquema se asume https, que es lo que pide RNF-06', () {
      expect(
        Servidor.normalizar('timbre.micolegio.edu.co').origen,
        'https://timbre.micolegio.edu.co',
      );
    });

    test('Se conserva el puerto', () {
      expect(
        Servidor.normalizar('http://192.168.1.50:8080').origen,
        'http://192.168.1.50:8080',
      );
    });

    test('Se quita la ruta: la app agrega /api sola', () {
      // Pegar la URL completa de la API es el error más fácil de cometer, y
      // sin esto acabaría pidiendo /api/api/auth/login.
      expect(
        Servidor.normalizar('https://colegio.edu.co/api').origen,
        'https://colegio.edu.co',
      );
      expect(
        Servidor.normalizar('https://colegio.edu.co/api/').origen,
        'https://colegio.edu.co',
      );
    });

    test('Se ignoran los espacios de sobra', () {
      expect(
        Servidor.normalizar('  https://colegio.edu.co  ').origen,
        'https://colegio.edu.co',
      );
    });

    test('Una dirección vacía se rechaza con un motivo', () {
      final resultado = Servidor.normalizar('   ');
      expect(resultado.origen, isNull);
      expect(resultado.error, isNotNull);
    });

    test('Un esquema que no es http ni https se rechaza', () {
      final resultado = Servidor.normalizar('ftp://colegio.edu.co');
      expect(resultado.origen, isNull);
      expect(resultado.error, contains('http'));
    });
  });

  group('Aviso de conexión sin cifrar (RNF-06)', () {
    test('http hacia internet se marca como inseguro', () {
      expect(Servidor.esInseguro('http://colegio.edu.co'), isTrue);
    });

    test('https nunca es inseguro', () {
      expect(Servidor.esInseguro('https://colegio.edu.co'), isFalse);
    });

    test('La red local no se marca: ahí no hay certificado posible', () {
      // El computador de desarrollo y un servidor dentro del colegio no salen
      // a internet, así que exigirles HTTPS sería ruido inútil.
      for (final local in [
        'http://localhost:8080',
        'http://127.0.0.1:8080',
        'http://10.0.2.2:8080',
        'http://192.168.1.50:8080',
        'http://172.16.0.4:8080',
      ]) {
        expect(Servidor.esInseguro(local), isFalse, reason: local);
      }
    });

    test('Una dirección parecida a la privada pero pública sí se marca', () {
      // 172.32 queda fuera del rango privado (172.16–172.31).
      expect(Servidor.esInseguro('http://172.32.0.4'), isTrue);
    });
  });

  group('Dónde quedan los endpoints', () {
    test('La app agrega /api al origen', () {
      expect(
        ApiClient.baseUrlDe('https://colegio.edu.co'),
        'https://colegio.edu.co/api',
      );
    });

    test('Cambiar de servidor cambia la base sin recrear el cliente', () {
      // Recrearlo perdería el token de la sesión abierta.
      final cliente = ApiClient(origen: 'http://127.0.0.1:8080');
      cliente.usarToken('token-de-prueba');

      cliente.usarServidor('https://colegio.edu.co');

      expect(cliente.dio.options.baseUrl, 'https://colegio.edu.co/api');
      expect(
        cliente.dio.options.headers['Authorization'],
        'Bearer token-de-prueba',
      );
    });
  });
}
