import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:swiftyring/core/auth/domain/auth_session.dart';

/// Guarda la sesión entre arranques de la app.
///
/// Se usa almacenamiento **seguro** (Keychain en iOS, EncryptedSharedPreferences
/// en Android) y no `SharedPreferences`, porque lo que se guarda es un JWT: con
/// él, cualquiera que lea el disco del dispositivo actúa como el docente dueño
/// de la sesión.
class SessionStorage {
  static const _clave = 'sesion_swiftyring';

  final FlutterSecureStorage _storage;

  SessionStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  Future<void> guardar(AuthSession sesion) {
    return _storage.write(key: _clave, value: jsonEncode(sesion.toJson()));
  }

  /// Devuelve `null` si no hay nada guardado o si lo guardado ya no se puede
  /// interpretar (por ejemplo, tras cambiar el formato de la sesión).
  Future<AuthSession?> leer() async {
    final crudo = await _storage.read(key: _clave);
    if (crudo == null) return null;

    try {
      final json = jsonDecode(crudo);
      if (json is! Map<String, dynamic>) return null;
      return AuthSession.fromJson(json);
    } on FormatException {
      return null;
    }
  }

  Future<void> borrar() => _storage.delete(key: _clave);
}
