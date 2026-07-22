import 'package:dio/dio.dart';

import '../../domain/entities/auth_session.dart';
import '../../domain/exceptions/auth_exception.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/login_request.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDatasource remoteDatasource;

  AuthRepositoryImpl(this.remoteDatasource);

  @override
  Future<AuthSession> login({required String email, required String password}) async {
    try {
      final response = await remoteDatasource.login(
        LoginRequest(email: email, password: password),
      );
      return AuthSession(
        token: response.token,
        nombre: response.usuario.nombre,
        email: response.usuario.email,
        rol: response.usuario.rol,
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      final reason = data is Map ? data['reason'] as String? : null;
      throw AuthException(reason ?? 'No se pudo iniciar sesión. Intenta de nuevo.');
    }
  }
}
