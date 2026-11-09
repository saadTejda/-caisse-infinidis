import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'api.dart';
import 'settings.dart';

Map<String, dynamic> asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> asList(dynamic v) => v is List ? v.map((e) => asMap(e)).toList() : <Map<String, dynamic>>[];

int asInt(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}') ?? (v is num ? v.toInt() : 0);

/// État de l'application préparateur : serveur, compte, file relue toutes les 15 s et commande ouverte.
class AppState extends ChangeNotifier {
  AppState._(this.prefs) : settings = PrepSettings(prefs);

  static late AppState instance;

  final SharedPreferences prefs;
  final PrepSettings settings;
  final _secure = const FlutterSecureStorage();
  Timer? _timer;
  DateTime _contextAt = DateTime.fromMillisecondsSinceEpoch(0);

  ApiClient? api;
  String serverUrl = '';
  String serverName = '';
  Map<String, dynamic>? user;
  Map<String, dynamic> context = {};
  Map<String, dynamic> feed = {};
  Map<String, dynamic>? order;
  bool online = true;
  String? feedError;
  int newOrders = 0;

  static Future<AppState> boot() async {
    final state = AppState._(await SharedPreferences.getInstance());
    instance = state;
    await state._load();
    return state;
  }

  bool get hasServer => serverUrl.isNotEmpty;
  bool get loggedIn => user != null && (api?.token ?? '').isNotEmpty;
  Map<String, dynamic> get abilities => asMap(context['abilities']);
  List<Map<String, dynamic>> get packagings => asList(context['packagings']);
  List<String> get holdReasons => (context['hold_reasons'] as List? ?? const []).map((e) => e.toString()).toList();
  Map<String, dynamic> get counts => asMap(feed['counts']);
  Map<String, dynamic> get today => asMap(feed['today']);
  List<Map<String, dynamic>> get queue => asList(feed['queue']);
  List<Map<String, dynamic>> get products => asList(feed['products']);
  List<Map<String, dynamic>> get done => asList(feed['done']);
  bool get locked => order != null && order!['prep'] == 'prepared';
  bool get complete => order != null && asInt(order!['done']) >= asInt(order!['total']) && order!['short'] != true;

  Future<void> _load() async {
    serverUrl = prefs.getString('server_url') ?? '';
    serverName = prefs.getString('server_name') ?? '';
    final token = await _secure.read(key: 'prep_token');
    final savedUser = prefs.getString('user');
    final savedContext = prefs.getString('context');
    if (savedContext != null) context = asMap(jsonDecode(savedContext));
    if (serverUrl.isNotEmpty) api = ApiClient(baseUrl: serverUrl, token: token);
    if (savedUser != null && (token ?? '').isNotEmpty) user = asMap(jsonDecode(savedUser));
    applyWake();
    if (loggedIn) {
      unawaited(loadContext());
      start();
    } else if (api != null) {
      unawaited(api!.ping().then(_rename).catchError((_) {}));
    }
  }

  /// Le nom affiché suit celui du serveur (Marque & adresse), même s'il change après l'installation.
  Future<void> _rename(String name) async {
    if (name.isEmpty || name == serverName) return;
    serverName = name;
    await prefs.setString('server_name', name);
    notifyListeners();
  }

  void applyWake() {
    if (settings.keepAwake && loggedIn) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  Future<String> setServer(String input) async {
    final url = ApiClient.normalize(input);
    if (url.isEmpty) throw ApiException('Saisissez l’adresse du serveur.');
    final client = ApiClient(baseUrl: url);
    final name = await client.ping();
    if (url != serverUrl) await _forget();
    serverUrl = url;
    serverName = name;
    api = ApiClient(baseUrl: url);
    await prefs.setString('server_url', url);
    await prefs.setString('server_name', name);
    notifyListeners();
    return name;
  }

  Future<void> login(String email, String password) async {
    if (api == null) throw ApiException('Choisissez d’abord le serveur.');
    final data = await api!.post('/login', {
      'email': email,
      'password': password,
      'device_name': settings.stationName.isNotEmpty ? settings.stationName : 'Tablette préparation',
      'platform': 'android',
      'app_version': '1.0',
    });
    final token = (data['token'] ?? '').toString();
    if (token.isEmpty) throw ApiException('Connexion refusée.');
    api!.token = token;
    await _secure.write(key: 'prep_token', value: token);
    user = asMap(data['user']);
    await prefs.setString('user', jsonEncode(user));
    await loadContext();
    applyWake();
    start();
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api?.post('/logout');
    } catch (_) {}
    await _forget();
    notifyListeners();
  }

  Future<void> _forget() async {
    stop();
    await _secure.delete(key: 'prep_token');
    await prefs.remove('user');
    await prefs.remove('context');
    api?.token = null;
    user = null;
    context = {};
    feed = {};
    order = null;
    applyWake();
  }

  Future<void> loadContext() async {
    try {
      _contextAt = DateTime.now();
      context = await call(() => api!.get('/context'));
      await prefs.setString('context', jsonEncode(context));
      await _rename((asMap(context['brand'])['name'] ?? '').toString());
      notifyListeners();
    } catch (_) {}
  }

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: asInt(context['refresh_seconds']) > 0 ? asInt(context['refresh_seconds']) : 15), (_) => refresh());
    unawaited(refresh());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Relit la file ; newOrders > 0 quand des commandes « À préparer » viennent d'arriver.
  Future<void> refresh() async {
    if (!loggedIn) return;
    if (DateTime.now().difference(_contextAt) > const Duration(minutes: 10)) unawaited(loadContext());
    try {
      final before = asInt(counts['todo']);
      final hadFeed = feed.isNotEmpty;
      feed = await call(() => api!.get('/feed'));
      online = true;
      feedError = null;
      newOrders = hadFeed && asInt(counts['todo']) > before ? asInt(counts['todo']) - before : 0;
    } on ApiException catch (e) {
      online = !e.network;
      feedError = e.message;
    }
    notifyListeners();
  }

  /// Appel avec déconnexion automatique si le jeton est refusé.
  Future<Map<String, dynamic>> call(Future<Map<String, dynamic>> Function() run) async {
    try {
      return await run();
    } on ApiException catch (e) {
      if (e.unauthorized) {
        await _forget();
        notifyListeners();
      }
      rethrow;
    }
  }

  void setOrder(Map<String, dynamic>? value) {
    order = value;
    notifyListeners();
  }

  Future<Map<String, dynamic>> open(String code) async {
    final data = await call(() => api!.post('/orders/open', {'code': code}));
    setOrder(asMap(data['order']));
    unawaited(refresh());
    return order!;
  }

  /// Article scanné : result = added / wrong / excess / done.
  Future<Map<String, dynamic>> scan(String code) async {
    final data = await call(() => api!.post('/orders/${order!['id']}/scan', {'code': code}));
    setOrder(asMap(data['order']));
    return data;
  }

  Future<void> setLine(int itemId, int quantity) async {
    final data = await call(() => api!.post('/orders/${order!['id']}/line', {'item_id': itemId, 'quantity': quantity}));
    setOrder(asMap(data['order']));
  }

  Future<void> hold(String reason) async {
    final data = await call(() => api!.post('/orders/${order!['id']}/hold', {'reason': reason}));
    setOrder(asMap(data['order']));
    unawaited(refresh());
  }

  Future<void> resume() async {
    final data = await call(() => api!.post('/orders/${order!['id']}/resume'));
    setOrder(asMap(data['order']));
    unawaited(refresh());
  }

  Future<void> finish({required int packagingId, required int packages, int? weight, bool force = false, String reason = ''}) async {
    final data = await call(() => api!.post('/orders/${order!['id']}/finish', {
          'packaging_id': packagingId,
          'packages': packages,
          if (weight != null && weight > 0) 'weight_grams': weight,
          'force': force,
          'reason': reason,
        }));
    setOrder(asMap(data['order']));
    unawaited(refresh());
  }

  Future<String> confirmLabel(String code) async {
    final data = await call(() => api!.post('/orders/${order!['id']}/label', {'code': code}));
    return (data['message'] ?? 'Étiquette contrôlée.').toString();
  }

  /// Commande suivante de la file (hors attente), ou null s'il n'y en a plus.
  Map<String, dynamic>? nextInQueue() {
    final current = order?['id'];
    for (final row in queue) {
      if (row['id'] != current && row['prep'] != 'on_hold') return row;
    }
    return null;
  }

  String imageUrl(dynamic variantId) => api!.uri('/products/$variantId/image').toString();
}
