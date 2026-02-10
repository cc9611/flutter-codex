import 'package:dio/dio.dart';

import 'api_service.dart';
import 'auth_token_store.dart';

class RestClient {
  RestClient._internal()
      : dio = Dio(
          BaseOptions(
            baseUrl: _baseUrl,
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 20),
          ),
        ) {
    dio.interceptors.addAll([
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = AuthTokenStore.instance.token;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        error: true,
      ),
    ]);

    api = ApiService(dio, baseUrl: _baseUrl);
  }

  static const String _baseUrl = 'https://api.example.com';

  static final RestClient instance = RestClient._internal();

  final Dio dio;
  late final ApiService api;
}
