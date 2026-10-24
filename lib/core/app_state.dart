import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'db.dart';
import 'models.dart';
import 'product_images.dart';

/// Résultat d'un encaissement : ticket à imprimer et indication hors ligne.
class SaleResult {
  SaleResult(this.ticket, {required this.offline, this.message});

  final Map<String, dynamic> ticket;
  final bool offline;
  final String? message;
}

class AppState extends ChangeNotifier {
  AppState._(this.db);

  static late AppState instance;

  final LocalDb db;
  final _secure = const FlutterSecureStorage();
  final _uuid = const Uuid();
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  Timer? _timer;
  bool _pushing = false;

  ApiClient? api;
  String serverUrl = '';
  String serverName = '';
  Map<String, dynamic>? user;
  Map<String, dynamic> context = {};
  bool online = false;
  int pending = 0;
  int errors = 0;
  String? lastSync;
  int catalogVersion = 0;
  String? syncMessage;
  bool syncing = false;

  static Future<AppState> boot() async {
    final state = AppState._(await LocalDb.open());
    instance = state;
    await state._load();
    return state;
  }

  bool get hasServer => serverUrl.isNotEmpty;
  bool get loggedIn => user != null && (api?.token ?? '').isNotEmpty;
  Map<String, dynamic> get abilities => Map<String, dynamic>.from(context['abilities'] ?? {});
  Map<String, dynamic> get pricing => Map<String, dynamic>.from(context['pricing'] ?? {});
  Map<String, dynamic>? get store => context['store'] == null ? null : Map<String, dynamic>.from(context['store']);
  Map<String, dynamic>? get session => context['session'] == null ? null : Map<String, dynamic>.from(context['session']);
  Map<String, dynamic> get company => Map<String, dynamic>.from(context['company'] ?? {});
  List<Map<String, dynamic>> get stores => (context['stores'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
  Map<String, String> get methods => Map<String, dynamic>.from(context['methods'] ?? {}).map((k, v) => MapEntry(k, v.toString()));
  String get currency => (pricing['currency'] ?? 'DH').toString();

  Future<void> _load() async {
    serverUrl = (await db.getValue('server_url') ?? '').toString();
    serverName = (await db.getValue('server_name') ?? '').toString();
    final token = await _secure.read(key: 'token');
    final savedUser = await db.getValue('user');
    context = Map<String, dynamic>.from(await db.getValue('context') ?? {});
    lastSync = (await db.getValue('last_sync'))?.toString();
    if (serverUrl.isNotEmpty) api = ApiClient(baseUrl: serverUrl, token: token);
    if (savedUser is Map && (token ?? '').isNotEmpty) user = Map<String, dynamic>.from(savedUser);
    await _counts();
    _connectivity = Connectivity().onConnectivityChanged.listen((_) => checkOnline());
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => checkOnline());
    unawaited(checkOnline());
  }

  @override
  void dispose() {
    _connectivity?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _counts() async {
    pending = await db.pendingCount();
    errors = await db.errorCount();
  }

  /// En ligne = le serveur répond. Au retour de la connexion, les ventes en attente partent seules.
  Future<bool> checkOnline() async {
    if (api == null) return false;
    bool now;
    try {
      await api!.ping();
      now = true;
    } catch (_) {
      now = false;
    }
    final changed = now != online;
    online = now;
    if (changed) notifyListeners();
    if (online && loggedIn) unawaited(pushOutbox());
    return online;
  }

  Future<String> setServer(String input) async {
    final url = ApiClient.normalize(input);
    if (url.isEmpty) throw ApiException('Saisissez l’adresse du serveur.');
    final client = ApiClient(baseUrl: url);
    final name = await client.ping();
    if (serverUrl.isNotEmpty && serverUrl != url) {
      await db.wipe();
      await ProductImageStore.instance.clear();
      await _secure.delete(key: 'token');
      user = null;
      context = {};
    }
    serverUrl = url;
    serverName = name;
    api = client;
    online = true;
    await db.setValue('server_url', url);
    await db.setValue('server_name', name);
    notifyListeners();
    return name;
  }

  Future<void> login(String email, String password) async {
    final data = await api!.post('/login', {'email': email, 'password': password, 'device_name': 'Caisse Android', 'platform': 'android', 'app_version': '1.0.0'});
    api!.token = data['token'].toString();
    user = Map<String, dynamic>.from(data['user'] as Map);
    await _secure.write(key: 'token', value: api!.token);
    await db.setValue('user', user);
    online = true;
    await syncAll();
  }

  Future<void> logout({bool force = false}) async {
    if (!force) {
      try {
        await api?.post('/logout');
      } catch (_) {}
    }
    api?.token = null;
    user = null;
    await _secure.delete(key: 'token');
    await db.setValue('user', null);
    notifyListeners();
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on ApiException catch (e) {
      if (e.unauthorized) await logout(force: true);
      rethrow;
    }
  }

  Future<void> syncContext({int? storeId}) => _guard(() async {
        final data = await api!.get('/context', query: storeId != null ? {'store': '$storeId'} : (store != null ? {'store': '${store!['id']}'} : null));
        context = data;
        await db.setValue('context', data);
        notifyListeners();
      });

  Future<int> syncCatalog() async {
    int count = 0;
    await _guard(() async {
      final data = await api!.get('/catalog', query: store != null ? {'store': '${store!['id']}'} : null, timeout: const Duration(seconds: 90));
      final items = (data['items'] as List? ?? []).map((e) => Product.fromJson(Map<String, dynamic>.from(e))).toList();
      await db.replaceProducts(items);
      count = items.length;
      catalogVersion++;
      notifyListeners();
      unawaited(ProductImageStore.instance.prefetch(items));
    });
    return count;
  }

  Future<int> syncContacts() async {
    int count = 0;
    await _guard(() async {
      final data = await api!.get('/contacts', timeout: const Duration(seconds: 90));
      final items = (data['contacts'] as List? ?? []).map((e) => Contact.fromJson(Map<String, dynamic>.from(e))).toList();
      await db.replaceContacts(items);
      count = items.length;
    });
    return count;
  }

  /// Nouveau client (en ligne uniquement) : enregistré sur le serveur puis ajouté aux contacts de l'appareil.
  Future<Contact> createContact(Map<String, String> fields) async {
    late Contact contact;
    await _guard(() async {
      final data = await api!.post('/contacts', fields);
      contact = Contact.fromJson(Map<String, dynamic>.from(data['contact'] as Map));
      await db.saveContact(contact);
    });
    return contact;
  }

  /// Synchroniser : ventes en attente d'abord, puis caisse, produits et contacts.
  Future<String> syncAll({bool products = true, bool contacts = true}) async {
    if (syncing) return syncMessage ?? '';
    syncing = true;
    notifyListeners();
    try {
      final sent = await pushOutbox();
      await syncContext();
      final p = products ? await syncCatalog() : null;
      final c = contacts ? await syncContacts() : null;
      lastSync = DateTime.now().toIso8601String();
      await db.setValue('last_sync', lastSync);
      online = true;
      syncMessage = [
        if (sent > 0) '$sent vente(s) envoyée(s)',
        if (p != null) '$p produit(s)',
        if (c != null) '$c contact(s)',
      ].join(' · ');
      return syncMessage!.isEmpty ? 'Caisse à jour.' : syncMessage!;
    } on ApiException catch (e) {
      if (e.network) online = false;
      rethrow;
    } finally {
      syncing = false;
      await _counts();
      notifyListeners();
    }
  }

  Future<void> changeStore(int storeId) async {
    await syncContext(storeId: storeId);
    await syncCatalog();
    notifyListeners();
  }

  /// Envoie les ventes en attente (par lots, dans l'ordre). Retourne le nombre de ventes acceptées.
  Future<int> pushOutbox() async {
    if (_pushing || api == null || !loggedIn) return 0;
    _pushing = true;
    int accepted = 0;
    try {
      while (true) {
        final rows = await db.outbox(statuses: ['pending']);
        if (rows.isEmpty) break;
        final chunk = rows.take(20).toList();
        final data = await api!.post('/sales/batch', {'sales': chunk.map((r) => _decode(r['payload'])).toList()}, const Duration(seconds: 60));
        final results = (data['results'] as List? ?? []);
        bool progressed = false;
        for (final raw in results) {
          final r = Map<String, dynamic>.from(raw as Map);
          final uuid = r['request_uuid'].toString();
          if (r['ok'] == true) {
            final sale = Map<String, dynamic>.from(r['sale'] as Map);
            await db.markSent(uuid, sale['number'].toString());
            accepted++;
            progressed = true;
          } else {
            await db.markError(uuid, (r['message'] ?? 'Vente refusée').toString(), retry: r['retry'] == true);
            if (r['retry'] != true) progressed = true;
          }
        }
        if (!progressed) break;
      }
    } on ApiException catch (e) {
      if (e.unauthorized) await logout(force: true);
      if (e.network) online = false;
    } finally {
      _pushing = false;
      await _counts();
      notifyListeners();
    }
    return accepted;
  }

  Map<String, dynamic> _decode(Object? raw) => Map<String, dynamic>.from(jsonDecode(raw.toString()) as Map);

  Future<void> openSession(String float) => _guard(() async {
        await api!.post('/session/open', {'store_id': store?['id'], 'opening_float': float});
        await syncContext();
      });

  Future<Map<String, dynamic>> closeSession(String counted, String note) async {
    Map<String, dynamic> report = {};
    await _guard(() async {
      final id = session?['id'];
      final data = await api!.post('/session/$id/close', {'counted_cash': counted, 'close_note': note});
      report = Map<String, dynamic>.from(data['report'] as Map);
      await syncContext();
    });
    return report;
  }

  /// Encaissement : en ligne → envoi direct ; hors ligne (ou réseau coupé pendant l'envoi) → file d'attente.
  Future<SaleResult> checkout({
    required List<CartLine> lines,
    required Totals totals,
    required Map<String, dynamic> payment,
    Contact? contact,
    String? discountType,
    double discountValue = 0,
  }) async {
    final uuid = _uuid.v4();
    final payload = <String, dynamic>{
      'request_uuid': uuid,
      'store_id': store?['id'],
      'lines': lines.map((l) => {'variant_id': l.product.variantId, 'quantity': l.quantity}).toList(),
      if (discountType != null && discountValue > 0) 'discount': {'type': discountType, 'value': discountValue.toStringAsFixed(2)},
      if (contact != null) 'contact_id': contact.id,
      ...payment,
    };
    final credit = payment['credit'] == true;
    if (online) {
      try {
        final data = await api!.post('/sales', payload, const Duration(seconds: 30));
        final sale = Map<String, dynamic>.from(data['sale'] as Map);
        await _decrementStock(lines);
        return SaleResult(_serverTicket(sale), offline: false);
      } on ApiException catch (e) {
        if (e.unauthorized) {
          await logout(force: true);
          rethrow;
        }
        if (!e.network) rethrow;
        online = false;
        notifyListeners();
      }
    }
    if (credit) {
      throw ApiException('Connectez-vous à Internet pour vérifier le crédit du client.');
    }
    final soldAt = DateTime.now();
    payload['offline'] = true;
    payload['sold_at'] = soldAt.toUtc().toIso8601String();
    final count = ((await db.getValue('offline_counter')) as num? ?? 0).toInt() + 1;
    await db.setValue('offline_counter', count);
    final localNumber = 'HL-${count.toString().padLeft(5, '0')}';
    final ticket = _localTicket(localNumber, soldAt, lines, totals, payment, contact);
    await db.enqueue(uuid: uuid, localNumber: localNumber, payload: payload, ticket: ticket);
    await _decrementStock(lines);
    await _counts();
    notifyListeners();
    return SaleResult(ticket, offline: true, message: 'Vente enregistrée hors ligne ($localNumber) : elle sera envoyée au retour de la connexion.');
  }

  Future<void> _decrementStock(List<CartLine> lines) async {
    for (final l in lines) {
      l.product.storeAvailable -= l.quantity;
      await db.saveProduct(l.product);
    }
  }

  Map<String, dynamic> _serverTicket(Map<String, dynamic> sale) => {
        'number': sale['number'],
        'date': sale['date'],
        'store': sale['store'],
        'cashier': sale['cashier'],
        'lines': (sale['lines'] as List? ?? []).map((l) => {'label': l['label'], 'quantity': l['quantity'], 'unit_price': l['unit_price'], 'total': l['total']}).toList(),
        'discount': sale['discount'],
        'total_tax': sale['total_tax'],
        'vat': sale['vat'],
        'total': sale['total'],
        'payments': (sale['payments'] as List? ?? []).map((p) => {'method': p['method'], 'amount': p['amount']}).toList(),
        'change': sale['change'],
        'due': sale['due'],
        'contact': sale['contact'] is Map ? (sale['contact'] as Map)['name'] : null,
        'offline': false,
      };

  Map<String, dynamic> _localTicket(String number, DateTime at, List<CartLine> lines, Totals totals, Map<String, dynamic> payment, Contact? contact) {
    final cash = toNum(payment['cash_received']);
    final others = (payment['payments'] as List? ?? []).map((p) => Map<String, dynamic>.from(p as Map)).toList();
    final nonCash = others.fold<double>(0, (s, p) => s + toNum(p['amount']));
    final cashApplied = (totals.total - nonCash).clamp(0, cash).toDouble();
    return {
      'number': number,
      'date': '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')}/${at.year} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
      'store': store?['name'] ?? '',
      'cashier': user?['name'] ?? '',
      'lines': lines.map((l) => {'label': l.product.label, 'quantity': l.quantity, 'unit_price': (l.product.price ?? 0).toStringAsFixed(2), 'total': l.gross.toStringAsFixed(2)}).toList(),
      'discount': totals.discount.toStringAsFixed(2),
      'total_tax': totals.tax.toStringAsFixed(2),
      'vat': pricing['vat'] == true,
      'total': totals.total.toStringAsFixed(2),
      'payments': [
        ...others.map((p) => {'method': methods[p['method']] ?? p['method'], 'amount': toNum(p['amount']).toStringAsFixed(2)}),
        if (cashApplied > 0) {'method': methods['cash'] ?? 'Espèces', 'amount': cashApplied.toStringAsFixed(2)},
      ],
      'change': (cash - cashApplied).clamp(0, double.infinity).toStringAsFixed(2),
      'due': '0.00',
      'contact': contact?.name,
      'offline': true,
    };
  }
}