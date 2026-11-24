import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kHost = 'api_host';
const _kToken = 'api_token';

class SessionStore {
  Future<String?> getHost() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kHost);
  }

  Future<void> setHost(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHost, host.replaceAll(RegExp(r'/+$'), ''));
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kToken);
  }

  Future<void> setToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_kToken);
    } else {
      await prefs.setString(_kToken, token);
    }
  }

  Future<void> clearAuth() => setToken(null);
}

final sessionStoreProvider = Provider<SessionStore>((_) => SessionStore());

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final store = ref.read(sessionStoreProvider);
        final host = await store.getHost();
        final token = await store.getToken();
        if (host != null && host.isNotEmpty) {
          options.baseUrl = host;
        }
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ),
  );

  return dio;
});
