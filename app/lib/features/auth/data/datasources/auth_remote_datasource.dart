import 'package:dio/dio.dart';

import '../models/login_request.dart';
import '../models/login_response.dart';

class AuthRemoteDatasource {
  final Dio dio;

  AuthRemoteDatasource(this.dio);

  Future<LoginResponse> login(LoginRequest request) async {
    final response = await dio.post('/login', data: request.toJson());
    return LoginResponse.fromJson(response.data as Map<String, dynamic>);
  }
}
