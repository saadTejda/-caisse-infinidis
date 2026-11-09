import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Erreur renvoyée par le serveur ou le réseau, avec un message lisible.
class ApiException implements Exception {
  ApiException(this.message, {this.status = 0, this.network = false});

  final String message;
  final int status;
  final bool network;

  bool get unauthorized => status == 401;

  @override
  String toString() => message;
}

/// Appels à l'API préparateur /api/prep/v1 du serveur INFINIDIS Gestion.
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

  Uri uri(String path, [Map<String, String>? query]) => Uri.parse('$baseUrl/api/prep/v1$path').replace(queryParameters: query);

  Map<String, String> get authHeaders => {if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token'};

  Map<String, String> get _headers => {'Accept': 'application/json', 'Content-Type': 'application/json', ...authHeaders};

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query, Duration? timeout}) =>
      _send(() => http.get(uri(path, query), headers: _headers).timeout(timeout ?? _timeout));

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) =>
      _send(() => http.post(uri(path), headers: _headers, body: jsonEncode(body ?? {})).timeout(_timeout));

  /// Page HTML (étiquette) avec le jeton.
  Future<String> html(String path, Map<String, String> query) async {
    try {
      final response = await http.get(uri(path, query), headers: {'Accept': 'text/html', ...authHeaders}).timeout(_timeout);
      if (response.statusCode == 401) throw ApiException('Session expirée : reconnectez-vous.', status: 401);
      if (response.statusCode != 200) throw ApiException('Étiquette introuvable (${response.statusCode}).', status: response.statusCode);
      return utf8.decode(response.bodyBytes);
    } on TimeoutException {
      throw ApiException('Le serveur ne répond pas (délai dépassé).', network: true);
    } on SocketException {
      throw ApiException('Pas de connexion au serveur.', network: true);
    } on http.ClientException {
      throw ApiException('Pas de connexion au serveur.', network: true);
    }
  }

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
    String message = (data['message'] ?? '').toString();
    final errors = data['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) message = first.first.toString();
    }
    if (message.isEmpty) {
      message = response.statusCode >= 500 ? 'Erreur du serveur (${response.statusCode}).' : 'Action refusée (${response.statusCode}).';
    }
    throw ApiException(message, status: response.statusCode, network: response.statusCode >= 500);
  }

  /// Vérifie qu'une adresse est bien un serveur INFINIDIS Gestion avec l'API préparation.
  Future<String> ping() async {
    final data = await get('/ping', timeout: const Duration(seconds: 10));
    if (data['app'] != 'infinidis-preparation') throw ApiException('Ce serveur n’a pas l’API préparation (mettez à jour le site).');
    return (data['name'] ?? 'INFINIDIS Gestion').toString();
  }
}
