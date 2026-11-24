import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/staff_user.dart';

const _kHost = 'api_host';
const _kToken = 'api_token';
const _kUser = 'api_user';

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

  Future<void> setUser(StaffUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUser, jsonEncode(user.toJson()));
  }

  Future<StaffUser> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kUser);
    if (raw == null || raw.isEmpty) return StaffUser.empty;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return StaffUser.empty;
    return StaffUser.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> clearAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUser);
  }
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
