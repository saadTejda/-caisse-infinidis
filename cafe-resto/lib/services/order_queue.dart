import 'package:dio/dio.dart';

import '../db/local_store.dart';

class OrderQueue {
  OrderQueue(this._dio, this._store);

  final Dio _dio;
  final LocalStore _store;

  Future<Map<String, dynamic>> checkout({
    required Map<String, dynamic> payload,
    required String idempotencyKey,
    required bool online,
  }) async {
    final body = Map<String, dynamic>.from(payload);
    body['client_created_at'] = body['client_created_at'] ?? DateTime.now().toUtc().toIso8601String();

    if (!online) {
      await _store.enqueueOrder(idempotencyKey, body, body['client_created_at'] as String);
      return {
        'offline': true,
        'idempotency_key': idempotencyKey,
        'order': null,
      };
    }

    try {
      final response = await _dio.post(
        '/api/v1/orders',
        data: body,
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      return {
        'offline': false,
        'idempotency_key': idempotencyKey,
        'order': response.data['data'] ?? response.data,
      };
    } on DioException catch (error) {
      if (_isNetworkError(error)) {
        await _store.enqueueOrder(idempotencyKey, body, body['client_created_at'] as String);
        return {
          'offline': true,
          'idempotency_key': idempotencyKey,
          'order': null,
        };
      }
      rethrow;
    }
  }

  Future<int> flush() async {
    final pending = await _store.pendingOrders();
    var synced = 0;
    for (final item in pending) {
      final id = item['id'] as String;
      final payload = Map<String, dynamic>.from(item['payload'] as Map);
      try {
        await _dio.post(
          '/api/v1/orders',
          data: payload,
          options: Options(headers: {'Idempotency-Key': id}),
        );
        await _store.removePending(id);
        synced++;
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        if (status == 200 || status == 201) {
          await _store.removePending(id);
          synced++;
          continue;
        }
        // Idempotent replay conflict with same key should still clear.
        if (status == 409 || status == 422 && _looksLikeReplay(error)) {
          await _store.removePending(id);
          synced++;
          continue;
        }
        if (_isNetworkError(error)) {
          break;
        }
        await _store.bumpPending(id, error.message ?? 'error');
      }
    }
    return synced;
  }

  Future<int> pendingCount() async => (await _store.pendingOrders()).length;

  bool _isNetworkError(DioException error) {
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.unknown;
  }

  bool _looksLikeReplay(DioException error) {
    final data = error.response?.data;
    return data.toString().contains('idempot');
  }
}
