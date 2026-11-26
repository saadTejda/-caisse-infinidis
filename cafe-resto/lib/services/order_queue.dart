import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../db/local_store.dart';

Map<String, dynamic> stripPrivate(Map<String, dynamic> body) {
  return {
    for (final entry in body.entries)
      if (!entry.key.startsWith('_')) entry.key: entry.value,
  };
}

String queuePath(String op, {Object? orderId, Object? deliveryId}) {
  return switch (op) {
    'sale_update' => '/api/v1/orders/$orderId/changes',
    'sale_cancel' => '/api/v1/orders/$orderId/cancel',
    'delivery_assign' => '/api/v1/deliveries/$deliveryId/assign',
    'delivery_status' => '/api/v1/deliveries/$deliveryId/status',
    'driver_payment' => '/api/v1/deliveries/$deliveryId/driver-payment',
    _ => '/api/v1/orders',
  };
}

class OrderQueue {
  OrderQueue(this._dio, this._store);

  final Dio _dio;
  final LocalStore _store;
  final flushing = ValueNotifier<bool>(false);
  bool _flushing = false;

  Future<Map<String, dynamic>> checkout({
    required Map<String, dynamic> payload,
    required String idempotencyKey,
    required bool online,
  }) async {
    final body = Map<String, dynamic>.from(payload);
    body['client_created_at'] = body['client_created_at'] ?? DateTime.now().toUtc().toIso8601String();

    if (!online) {
      return _park(idempotencyKey, body);
    }

    try {
      final response = await _dio.post(
        '/api/v1/orders',
        data: stripPrivate(body),
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      return {
        'offline': false,
        'idempotency_key': idempotencyKey,
        'order': response.data['data'] ?? response.data,
      };
    } on DioException catch (error) {
      if (_isNetworkError(error)) {
        return _park(idempotencyKey, body);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _park(String key, Map<String, dynamic> body) async {
    await _store.enqueueOrder(key, body, body['client_created_at'] as String);
    final number = await _store.nextOfflineNumber();
    return {
      'offline': true,
      'idempotency_key': key,
      'local_ref': 'HL-${number.toString().padLeft(5, '0')}',
      'order': null,
    };
  }

  Future<void> enqueueOperation(String id, Map<String, dynamic> payload) async {
    await _store.enqueueOrder(id, payload, DateTime.now().toUtc().toIso8601String());
  }

  Future<void> updatePending(String id, Map<String, dynamic> payload) async {
    await _store.updatePending(id, payload);
  }

  Future<void> deletePending(String id) async {
    await _store.removePending(id);
  }

  Future<int> errorCount() async {
    final pending = await _store.pendingOrders();
    return pending.where((item) => '${item['last_error'] ?? ''}'.isNotEmpty).length;
  }

  Future<List<Map<String, dynamic>>> items() => _store.pendingOrders();

  Future<int> flush() async {
    if (_flushing) return 0;
    _flushing = true;
    flushing.value = true;
    final pending = await _store.pendingOrders();
    var synced = 0;
    try {
      for (final item in pending) {
        final id = item['id'] as String;
        final payload = Map<String, dynamic>.from(item['payload'] as Map);
        final op = '${payload['_op'] ?? 'sale'}';
        final orderId = payload['_order_id'];
        final deliveryId = payload['_delivery_id'];
        try {
          await _dio.post(
            queuePath(op, orderId: orderId, deliveryId: deliveryId),
            data: stripPrivate(payload),
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
          if (status == 404 || status == 405) {
            await _store.bumpPending(id, 'Le serveur ne connaît pas encore cette opération.');
            continue;
          }
          if (status == 409 || status == 422 && _looksLikeReplay(error)) {
            await _store.removePending(id);
            synced++;
            continue;
          }
          if (_isNetworkError(error)) {
            await _store.bumpPending(id, 'Envoi interrompu. Ne recliquez pas, reprise automatique.');
            break;
          }
          await _store.bumpPending(id, error.message ?? 'error');
        }
      }
    } finally {
      _flushing = false;
      flushing.value = false;
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
