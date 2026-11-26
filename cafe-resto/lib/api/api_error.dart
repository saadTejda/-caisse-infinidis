import 'package:dio/dio.dart';

String apiMessage(Object error, {String fallback = 'Action refusée.'}) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final errors = data['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) return '${first.first}';
        return '$first';
      }
      final message = data['message']?.toString();
      if (message != null && message.isNotEmpty && !_genericMessage(message)) return message;
    }
    final status = error.response?.statusCode;
    if (status == 401) return 'Session expirée.';
    if (status == 403) return 'Permission refusée.';
    if (status == 404) return 'Introuvable.';
    if (status == 422) return 'Données refusées.';
  }
  return fallback;
}

bool _genericMessage(String message) {
  final lower = message.toLowerCase();
  return lower == 'not found' ||
      lower == 'server error' ||
      lower.contains('could not be found') ||
      lower.contains('no query results');
}

List<Map<String, dynamic>> apiList(dynamic body) {
  final raw = body is Map && body['data'] is List ? body['data'] : body;
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
}

Map<String, dynamic> apiMap(dynamic body) {
  if (body is Map && body['data'] is Map) return Map<String, dynamic>.from(body['data'] as Map);
  if (body is Map) return Map<String, dynamic>.from(body);
  return const {};
}
