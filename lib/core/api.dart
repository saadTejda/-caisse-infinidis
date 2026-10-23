import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Erreur renvoyée par le serveur ou le réseau, avec un message lisible.
class ApiException implements Exception {
  ApiException(this.message, {this.status = 0, this.network = false, this.errors = const {}});

  final String message;
  final int status;
  final bool network;
  final Map<String, dynamic> errors;

  bool get unauthorized => status == 401;

  @override
  String toString() => message;
}

/// Appels à l'API caisse /api/pos/v1 du serveur INFINIDIS Gestion.
class ApiClient {
  ApiClient({required this.baseUrl, this.token});

  String baseUrl;
  String? token;

  static const _timeout = Duration(seconds: 20);

  /// Adresse saisie : ajoute https:// si besoin et retire la barre finale.
  static String normalize(String input) {
    var url = input.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'https://$url';
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse('$baseUrl/api/pos/v1$path').replace(queryParameters: query);

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query, Duration? timeout}) =>
      _send(() => http.get(_uri(path, query), headers: _headers).timeout(timeout ?? _timeout));

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body, Duration? timeout]) =>
      _send(() => http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {})).timeout(timeout ?? _timeout));

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() call) async {
    http.Response response;
    try {
      response = await call();
    } on TimeoutException {
      throw ApiException('Le serveur ne répond pas (délai dépassé).', network: true);
    } on SocketException {
      throw ApiException('Pas de connexion au serveur.', network: true);
    } on http.ClientException {
      throw ApiException('Pas de connexion au serveur.', network: true);
    } on HandshakeException {
      throw ApiException('Connexion sécurisée impossible (certificat).', network: true);
    }
    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        throw ApiException('Réponse inattendue du serveur.', status: response.statusCode);
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    final errors = (data['errors'] is Map) ? Map<String, dynamic>.from(data['errors'] as Map) : <String, dynamic>{};
    String message = (data['message'] ?? '').toString();
    if (errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) message = first.first.toString();
    }
    if (message.isEmpty) {
      message = response.statusCode >= 500 ? 'Erreur du serveur (${response.statusCode}).' : 'Action refusée (${response.statusCode}).';
    }
    throw ApiException(message, status: response.statusCode, network: response.statusCode >= 500, errors: errors);
  }

  /// Vérifie qu'une adresse est bien un serveur INFINIDIS Gestion.
  Future<String> ping() async {
    final data = await get('/ping', timeout: const Duration(seconds: 10));
    if (data['app'] != 'infinidis-gestion') throw ApiException('Ce serveur n’est pas un serveur INFINIDIS Gestion.');
    return (data['name'] ?? 'INFINIDIS Gestion').toString();
  }
}
