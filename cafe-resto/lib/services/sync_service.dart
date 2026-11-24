import 'package:dio/dio.dart';

import '../db/local_store.dart';

class SyncService {
  SyncService(this._dio, this._store);

  final Dio _dio;
  final LocalStore _store;

  Future<Map<String, dynamic>> bootstrap({bool persist = true}) async {
    final response = await _dio.get('/api/v1/pos/bootstrap');
    final data = Map<String, dynamic>.from(response.data['data'] as Map);
    if (persist) {
      await _store.putJson('bootstrap', data);
      await _store.putJson('catalog', data['catalog']);
      await _store.putJson('settings', data['settings']);
      await _store.putJson('cash_status', data['cash_status']);
      await _store.putJson('user', data['user']);
      await _store.putJson('synced_at', data['synced_at']);
    }
    return data;
  }

  Future<Map<String, dynamic>?> cachedBootstrap() async {
    final raw = await _store.getJson('bootstrap');
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  Future<List<dynamic>> catalog() async {
    final raw = await _store.getJson('catalog');
    if (raw is List) {
      return raw;
    }
    return const [];
  }

  Future<Map<String, dynamic>> settings() async {
    final raw = await _store.getJson('settings');
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return {};
  }

  Future<Map<String, dynamic>> cashStatus() async {
    final raw = await _store.getJson('cash_status');
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return {
      'require_open_session': true,
      'session_open': false,
      'session_id': null,
    };
  }

  Future<void> refreshCashStatus() async {
    final response = await _dio.get('/api/v1/pos/cash-status');
    final data = Map<String, dynamic>.from(response.data['data'] as Map);
    await _store.putJson('cash_status', data);
    final boot = await cachedBootstrap();
    if (boot != null) {
      boot['cash_status'] = data;
      await _store.putJson('bootstrap', boot);
    }
  }
}
