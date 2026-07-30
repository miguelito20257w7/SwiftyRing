import 'package:dio/dio.dart';
import 'package:swiftyring/core/auth/data/login_dtos.dart';
import 'package:swiftyring/core/auth/domain/auth_exception.dart';

/// Único punto de la app que habla con `/api/auth`.
class AuthRemoteDatasource {
  final Dio dio;

  AuthRemoteDatasource({required this.dio});

  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    final response = await dio.post(
      '/auth/login',
      data: LoginRequest(email: email, password: password).toJson(),
    );

    if (response.statusCode == 200) {
      return LoginResponse.fromJson(response.data as Map<String, dynamic>);
    }

    throw AuthException(_razonDeError(response));
  }

  /// Vapor devuelve los errores como `{"error": true, "reason": "..."}`.
  String _razonDeError(Response<dynamic> response) {
    final data = response.data;
    if (data is Map && data['reason'] is String) {
      return data['reason'] as String;
    }
    if (response.statusCode == 401) {
      return 'Correo o contraseña incorrectos.';
    }
    return 'No se pudo iniciar sesión (código ${response.statusCode}).';
  }
}
