import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../db/list_cache.dart';
import '../providers/app_providers.dart';
import '../theme/pos_theme.dart';
import '../widgets/match_text.dart';
import 'pos_dialogs.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({
    super.key,
    this.onCheckoutDone,
    this.onOpenDrawer,
    this.onBack,
    this.onSync,
    this.onPrinters,
    this.userName = 'Caisse',
    this.pendingCount = 0,
    this.refreshToken = 0,
  });

  final Future<void> Function()? onCheckoutDone;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onBack;
  final Future<void> Function()? onSync;
  final VoidCallback? onPrinters;
  final String userName;
  final int pendingCount;
  final int refreshToken;

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _CartLine {
  _CartLine({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    required this.color,
    this.modifiers = const [],
    this.measured = false,
    this.lineTotalOverride,
  });

  final int productId;
  final String name;
  final double unitPrice;
  final Color color;
  final List<PosModifier> modifiers;
  final bool measured;
  final double? lineTotalOverride;
  double quantity;

  String get comboKey {
    final ids = modifiers.map((modifier) => modifier.id).toList()..sort();
    return '$productId:${ids.join(',')}';
  }

  String get displayName {
    if (modifiers.isEmpty) return name;
    return '$name (${modifiers.map((modifier) => modifier.name).join(', ')})';
  }

  double get lineTotal => lineTotalOverride ?? unitPrice * quantity;
}

class _PosScreenState extends ConsumerState<PosScreen> {
  List<dynamic> _catalog = [];
  Map<String, dynamic> _settings = {};
  Map<String, dynamic> _cash = {};
  String? _category;
  bool _stockOnly = false;
  final List<_CartLine> _cart = [];
  String _orderType = 'dine_in';
  String _payment = 'cash';
  final _tendered = TextEditingController();
  final _kitchenNote = TextEditingController();
  final _search = TextEditingController();
  final _customerName = TextEditingController();
  final _customerPhone = TextEditingController();
  final _deliveryAddress = TextEditingController();
  final _deliveryNotes = TextEditingController();
  int? _zoneId;
  List<Map<String, dynamic>> _zones = [];
  bool _loading = true;
  String? _error;

  static const _palette = <Color>[
    Color(0xFF3E6B4F),
    Color(0xFFE0B433),
    Color(0xFF6A9BB5),
    Color(0xFFC4473A),
    Color(0xFFD2A15A),
    Color(0xFF8D5A38),
    Color(0xFFE07A2F),
    Color(0xFFC9842A),
    Color(0xFF5E7F6A),
    Color(0xFFB4533A),
    Color(0xFF4F7C8A),
    Color(0xFFC46B2C),
  ];

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      if (mounted) setState(() {});
    });
    _kitchenNote.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void didUpdateWidget(PosScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _reloadCash();
    }
  }

  @override
  void dispose() {
    _tendered.dispose();
    _kitchenNote.dispose();
    _search.dispose();
    _customerName.dispose();
    _customerPhone.dispose();
    _deliveryAddress.dispose();
    _deliveryNotes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final sync = ref.read(syncServiceProvider);
    final catalog = await sync.catalog();
    final settings = await sync.settings();
    final cash = await sync.cashStatus();
    if (!mounted) return;
    setState(() {
      _catalog = catalog;
      _settings = settings;
      _cash = cash;
      _orderType = '${settings['pos.default_order_type'] ?? 'dine_in'}';
      _payment = '${settings['pos.default_payment_method'] ?? 'cash'}';
      _loading = false;
    });
    await _loadZones();
  }

  Future<void> _reloadCash() async {
    final cash = await ref.read(syncServiceProvider).cashStatus();
    if (mounted) setState(() => _cash = cash);
  }

  List<String> get _categories {
    final names = <String>{};
    for (final item in _catalog) {
      final map = Map<String, dynamic>.from(item as Map);
      names.add('${map['category_name'] ?? 'Autres'}');
    }
    final list = names.toList()
      ..sort((a, b) {
        final rank = _categoryRank(a).compareTo(_categoryRank(b));
        if (rank != 0) return rank;
        return a.compareTo(b);
      });
    return list;
  }

  int _categoryRank(String name) {
    var rank = 1 << 20;
    for (final item in _catalog) {
      final map = Map<String, dynamic>.from(item as Map);
      if ('${map['category_name'] ?? 'Autres'}' != name) continue;
      final pos = map['category_position'] ?? map['category_sort'] ?? map['position'];
      final n = int.tryParse('$pos');
      if (n != null && n < rank) rank = n;
    }
    return rank;
  }

  int _count(String? category) {
    return _catalog.where((item) {
      final map = Map<String, dynamic>.from(item as Map);
      if (category != null && '${map['category_name'] ?? 'Autres'}' != category) {
        return false;
      }
      return _matchesSearch(map) && _stockVisible(map);
    }).length;
  }

  bool _matchesSearch(Map<String, dynamic> product) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    for (final key in const ['name', 'sku', 'barcode', 'code', 'reference']) {
      if ('${product[key] ?? ''}'.toLowerCase().contains(query)) return true;
    }
    return false;
  }

  bool _stockVisible(Map<String, dynamic> product) {
    if (!_stockOnly) return true;
    final stock = _stockOf(product);
    return stock == null || stock > 0;
  }

  num? _stockOf(Map<String, dynamic> product) {
    for (final key in const ['stock', 'stock_on_hand', 'quantity_on_hand']) {
      final value = num.tryParse('${product[key]}');
      if (value != null) return value;
    }
    return null;
  }

  List<Map<String, dynamic>> get _products {
    return _catalog
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((p) => _category == null || '${p['category_name']}' == _category)
        .where(_matchesSearch)
        .where(_stockVisible)
        .toList()
      ..sort((a, b) {
        final category = (int.tryParse('${a['category_sort']}') ?? 0).compareTo(int.tryParse('${b['category_sort']}') ?? 0);
        if (category != 0) return category;
        return (int.tryParse('${a['pos_position']}') ?? 0).compareTo(int.tryParse('${b['pos_position']}') ?? 0);
      });
  }

  bool get _deliveryEnabled {
    final value = _settings['delivery.enabled'];
    return value != false && value != 0 && value != '0' && value != 'false';
  }

  bool _settingOn(String key) {
    final value = _settings[key];
    return value == true || value == 1 || value == '1' || value == 'true';
  }

  double get _total => _cart.fold(0, (sum, line) => sum + line.lineTotal);

  double get _zoneFee {
    if (_orderType != 'delivery' || _zoneId == null) return 0;
    for (final zone in _zones) {
      if (int.tryParse('${zone['id']}') == _zoneId) {
        return double.tryParse('${zone['fee']}'.replaceAll(',', '.')) ?? 0;
      }
    }
    return 0;
  }

  double get _payable => _total + _zoneFee;

  String get _zoneName {
    for (final zone in _zones) {
      if (int.tryParse('${zone['id']}') == _zoneId) return '${zone['name']}';
    }
    return '';
  }

  int get _articleCount => _cart.fold<int>(0, (sum, line) => sum + (line.measured ? 1 : line.quantity.round()));

  bool get _deliveryReady {
    if (_customerName.text.trim().isEmpty || _deliveryAddress.text.trim().isEmpty) return false;
    if (_settingOn('delivery.require_phone') && _customerPhone.text.trim().isEmpty) return false;
    if (_settingOn('delivery.require_zone') && _zoneId == null) return false;
    return true;
  }

  Future<void> _loadZones() async {
    final store = ref.read(localStoreProvider);
    final cached = await loadList(store, 'zones_cache');
    final remembered = cached.where((zone) => zone['is_active'] != false).toList();
    if (mounted && remembered.isNotEmpty) setState(() => _zones = remembered);
    try {
      final response = await ref.read(dioProvider).get('/api/v1/delivery-zones');
      final zones = apiList(response.data);
      await saveList(store, 'zones_cache', zones);
      final active = zones.where((zone) => zone['is_active'] != false).toList();
      if (mounted) setState(() => _zones = active);
    } catch (_) {}
  }

  bool get _salesBlocked {
    final require = _cash['require_open_session'] == true;
    final open = _cash['session_open'] == true;
    return require && !open;
  }

  Color _tileColor(Map<String, dynamic> product) {
    final raw = product['color'] ?? product['tile_color'] ?? product['background_color'];
    final parsed = _parseHex(raw?.toString());
    if (parsed != null) return parsed;
    final id = int.tryParse('${product['id']}') ?? 0;
    return _palette[id.abs() % _palette.length];
  }

  Color? _parseHex(String? raw) {
    if (raw == null) return null;
    var hex = raw.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return null;
    return Color(value);
  }

  String _money(num value) {
    final parts = value.toStringAsFixed(2).split('.');
    return '${parts[0]},${parts[1]} DH';
  }

  Future<void> _addProduct(Map<String, dynamic> product) async {
    final groups = posModifierGroups(product);
    final unit = '${product['unit'] ?? 'piece'}';
    final price = double.tryParse('${product['sale_price']}'.replaceAll(',', '.')) ?? 0;
    final name = '${product['name']}';
    double? measuredQty;
    double? measuredTotal;
    if (posIsMeasured(unit)) {
      final weight = await showPosWeightDialog(
        context,
        productName: name,
        unitPrice: price,
        unit: unit,
      );
      if (weight == null || !mounted) return;
      measuredQty = weight.quantity;
      measuredTotal = weight.lineTotal;
    }
    var modifiers = const <PosModifier>[];
    if (groups.isNotEmpty) {
      final picked = await showPosExtrasDialog(context, productName: name, groups: groups);
      if (picked == null || !mounted) return;
      modifiers = picked;
    }
    final extra = modifiers.fold<double>(0, (sum, modifier) => sum + modifier.priceDelta);
    final id = product['id'] as int;
    setState(() {
      if (measuredQty == null) {
        final probe = _CartLine(
          productId: id,
          name: name,
          unitPrice: price + extra,
          quantity: 1,
          color: _tileColor(product),
          modifiers: modifiers,
        );
        final existing = _cart.where((line) => !line.measured && line.comboKey == probe.comboKey).toList();
        if (existing.isNotEmpty) {
          existing.first.quantity += 1;
          return;
        }
      }
      _cart.add(
        _CartLine(
          productId: id,
          name: name,
          unitPrice: price + extra,
          quantity: measuredQty ?? 1,
          color: _tileColor(product),
          modifiers: modifiers,
          measured: measuredQty != null,
          lineTotalOverride: measuredTotal == null ? null : measuredTotal + extra * measuredQty!,
        ),
      );
    });
  }

  Future<void> _encaisser() async {
    if (_cart.isEmpty) return;
    if (_orderType == 'delivery' && !_deliveryReady) {
      setState(() => _error = 'Complétez la livraison : client, adresse, et zone ou téléphone si exigés.');
      return;
    }
    final choice = await showPosPayDialog(
      context,
      total: _total,
      deliveryFee: _zoneFee,
      initialMethod: _salesBlocked ? 'card' : _payment,
      cashBlocked: _salesBlocked,
    );
    if (choice == null || !mounted) return;
    setState(() {
      _payment = choice.method;
      _tendered.text = choice.tendered == null ? '' : choice.tendered!.toStringAsFixed(2);
    });
    await _checkout();
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) {
      setState(() => _error = 'Panier vide.');
      return;
    }
    final online = ref.read(onlineProvider).valueOrNull ?? false;
    if (!online && _salesBlocked) {
      setState(() => _error = 'Connectez-vous pour ouvrir la caisse. Hors ligne, seule une caisse déjà ouverte peut vendre.');
      return;
    }
    if (_payment == 'cash' && _salesBlocked) {
      setState(() => _error = 'Ouvrez le tiroir pour encaisser en espèces.');
      return;
    }
    if (_orderType == 'delivery' && !_deliveryReady) {
      setState(() => _error = 'Complétez la livraison : client, adresse, et zone ou téléphone si exigés.');
      return;
    }

    final tendered = _payment == 'cash'
        ? double.tryParse(_tendered.text.replaceAll(',', '.'))
        : _payable;
    if (_payment == 'cash' && (tendered == null || tendered + 0.001 < _payable)) {
      setState(() => _error = 'Montant reçu insuffisant.');
      return;
    }

    setState(() {
      _error = null;
      _loading = true;
    });

    final key = const Uuid().v4();
    final payload = {
      'type': _orderType,
      'payment_method': _payment,
      if (_payment == 'cash') 'tendered': tendered,
      'kitchen_note': _kitchenNote.text.trim().isEmpty ? null : _kitchenNote.text.trim(),
      if (_orderType == 'delivery') ...{
        'customer_name': _customerName.text.trim(),
        'customer_phone': _customerPhone.text.trim().isEmpty ? null : _customerPhone.text.trim(),
        'delivery_address': _deliveryAddress.text.trim(),
        'delivery_notes': _deliveryNotes.text.trim().isEmpty ? null : _deliveryNotes.text.trim(),
        'delivery_zone_id': _zoneId,
      },
      'lines': _cart
          .map(
            (l) => {
              'product_id': l.productId,
              'quantity': l.quantity,
              'modifiers': l.modifiers.map((modifier) => modifier.id).toList(),
            },
          )
          .toList(),
      'client_created_at': DateTime.now().toUtc().toIso8601String(),
      '_local_total': _payable,
    };

    try {
      final result = await ref.read(orderQueueProvider).checkout(
            payload: payload,
            idempotencyKey: key,
            online: online,
          );

      final cartSnapshot = _cart
          .map(
            (l) => {
              'name': l.displayName,
              'quantity': l.quantity,
              'line_total': l.lineTotal.toStringAsFixed(2),
            },
          )
          .toList();
      final totalStr = _total.toStringAsFixed(2);
      final note = _kitchenNote.text.trim();

      if (result['offline'] == true) {
        final lines = (payload['lines'] as List).map((line) => Map<String, dynamic>.from(line as Map)).toList();
        await ref.read(syncServiceProvider).adjustStock(lines, sign: -1);
      }
      String publicRef = result['offline'] == true ? '${result['local_ref'] ?? 'HL'}' : 'TICKET';
      final order = result['order'];
      if (order is Map && order['public_ref'] != null) {
        publicRef = '${order['public_ref']}';
      }

      try {
        await ref.read(printServiceProvider).printSale(
              settings: _settings,
              publicRef: publicRef,
              cartLines: cartSnapshot,
              total: totalStr,
              orderType: _orderType,
              kitchenNote: note.isEmpty ? null : note,
              taxLine: order is Map && order['tax_enabled'] == true ? 'TVA ${order['tax_total']}' : null,
              openDrawer: _payment == 'cash',
            );
      } catch (_) {
        // Impression best-effort.
      }

      final snapshot = List<Map<String, dynamic>>.from(cartSnapshot);
      setState(() {
        _cart.clear();
        _kitchenNote.clear();
        _tendered.clear();
        _customerName.clear();
        _customerPhone.clear();
        _deliveryAddress.clear();
        _deliveryNotes.clear();
        _zoneId = null;
      });
      await widget.onCheckoutDone?.call();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _ReceiptDialog(
          order: order is Map ? Map<String, dynamic>.from(order) : null,
          fallbackLines: snapshot,
          fallbackTotal: totalStr,
          footer: '${_settings['business.ticket_footer'] ?? ''}',
          logoUrl: '${_settings['business.logo_url'] ?? ''}',
          businessName: '${_settings['business.name'] ?? 'Caisse'}',
          offline: result['offline'] == true,
        ),
      );
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.data?['message']?.toString() ??
            e.response?.data?['errors']?.toString() ??
            'Encaissement impossible.';
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _catalog.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final canPay = _cart.isNotEmpty && !_loading;

    return SafeArea(
      child: Column(
        children: [
          _header(),
          if (_salesBlocked) _drawerBanner(),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _catalogPane()),
                _orderPane(canPay),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPending() async {
    final queue = ref.read(orderQueueProvider);
    final items = await queue.pendingCount() == 0 ? <Map<String, dynamic>>[] : await ref.read(localStoreProvider).pendingOrders();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ventes en attente'),
        content: SizedBox(
          width: 420,
          child: items.isEmpty
              ? const Text('Aucune vente en attente.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in items)
                      ListTile(
                        title: Text('${item['id']}'.substring(0, 8)),
                        subtitle: Text('${item['last_error'] ?? 'Pas encore envoyée'}'),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            TextButton(onPressed: () => _editPending(item), child: const Text('Modifier')),
                            TextButton(onPressed: () => _dropPending(item), child: const Text('Supprimer')),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
      ),
    );
  }

  Future<void> _editPending(Map<String, dynamic> item) async {
    final payload = Map<String, dynamic>.from(item['payload'] as Map);
    final lines = (payload['lines'] as List?)?.map((line) => Map<String, dynamic>.from(line as Map)).toList() ?? [];
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Modifier avant envoi'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final line in lines)
                Row(
                  children: [
                    Expanded(child: Text('Produit ${line['product_id']}')),
                    IconButton(
                      onPressed: () => setLocal(() => line['quantity'] = (num.tryParse('${line['quantity']}') ?? 1) - 1),
                      icon: const Icon(Icons.remove),
                    ),
                    Text('${line['quantity']}'),
                    IconButton(
                      onPressed: () => setLocal(() => line['quantity'] = (num.tryParse('${line['quantity']}') ?? 0) + 1),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final kept = lines.where((line) => (num.tryParse('${line['quantity']}') ?? 0) > 0).toList();
    payload['lines'] = kept;
    await ref.read(orderQueueProvider).updatePending('${item['id']}', payload);
    if (mounted) Navigator.of(context).pop();
    await widget.onCheckoutDone?.call();
  }

  Future<void> _dropPending(Map<String, dynamic> item) async {
    final payload = Map<String, dynamic>.from(item['payload'] as Map);
    final lines = (payload['lines'] as List?)?.map((line) => Map<String, dynamic>.from(line as Map)).toList() ?? [];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette vente'),
        content: const Text('Elle ne sera pas envoyée. Le stock local de ces articles sera remis.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    if ('${payload['_op'] ?? 'sale'}' == 'sale') {
      await ref.read(syncServiceProvider).adjustStock(lines, sign: 1);
    }
    await ref.read(orderQueueProvider).deletePending('${item['id']}');
    if (mounted) Navigator.of(context).pop();
    await widget.onCheckoutDone?.call();
  }

  Widget _header() {
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
        child: Row(
          children: [
            TextButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Retour'),
            ),
            PopupMenuButton<String>(
              tooltip: 'Actions',
              onSelected: (value) {
                if (value == 'sync') widget.onSync?.call();
                if (value == 'print') widget.onPrinters?.call();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'sync',
                  child: Text(
                    widget.pendingCount > 0
                        ? 'Synchroniser (${widget.pendingCount})'
                        : 'Synchroniser',
                  ),
                ),
                const PopupMenuItem(value: 'print', child: Text('Imprimantes')),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Carte',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: PosColors.ink),
                  ),
                  TextButton(
                    onPressed: widget.pendingCount > 0 ? _showPending : null,
                    child: Text(
                      widget.pendingCount > 0
                          ? '${widget.userName} · ${widget.pendingCount} en attente'
                          : widget.userName,
                      style: const TextStyle(fontSize: 12, color: PosColors.muted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Material(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () async {
                    final value = await showPosTextPad(
                      context,
                      title: 'Rechercher un produit',
                      initial: _search.text,
                      hint: 'Rechercher un produit',
                    );
                    if (value == null) return;
                    _search.text = value;
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.search, size: 20, color: PosColors.muted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _search.text.isEmpty ? 'Rechercher un produit' : _search.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _search.text.isEmpty ? PosColors.muted : PosColors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: PosColors.line),
              ),
              child: const Text('DH', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerBanner() {
    return Container(
      color: const Color(0xFFFFF6E8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Les espèces exigent un tiroir ouvert. La carte reste possible.',
              style: TextStyle(color: Color(0xFFC2410C), fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: widget.onOpenDrawer,
            child: const Text(
              'Ouvrir le tiroir',
              style: TextStyle(color: Color(0xFFC2410C), fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _catalogPane() {
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            children: [
              _categoryChip(null, 'Tous (${_count(null)})', null),
              _stockChip(),
              ..._categories.indexed.map((entry) => _categoryChip(entry.$2, '${entry.$2} (${_count(entry.$2)})', entry.$1)),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cols = (constraints.maxWidth / 168).floor().clamp(2, 8);
              if (_products.isEmpty) {
                final filtered = _search.text.trim().isNotEmpty || _stockOnly || _category != null;
                return Center(
                  child: Text(filtered ? 'Aucun résultat' : 'Aucun produit', style: const TextStyle(color: PosColors.muted)),
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  childAspectRatio: 0.82,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: _products.length,
                itemBuilder: (context, index) => _productCard(_products[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  static const _categoryColors = <Color>[
    PosColors.info,
    PosColors.warning,
    PosColors.progress,
    PosColors.success,
    PosColors.paid,
    PosColors.accent,
  ];

  Widget _stockChip() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: _stockOnly ? PosColors.success : Colors.white,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => setState(() => _stockOnly = !_stockOnly),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _stockOnly ? PosColors.success : PosColors.line),
            ),
            child: Text(
              'En stock',
              style: TextStyle(color: _stockOnly ? Colors.white : PosColors.ink, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryChip(String? value, String label, int? colorIndex) {
    final selected = _category == value;
    final tint = colorIndex == null ? PosColors.ink : _categoryColors[colorIndex % _categoryColors.length];
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? tint : Colors.white,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => setState(() => _category = value),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: selected ? tint : tint.withValues(alpha: 0.45)),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : tint,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _productCard(Map<String, dynamic> product) {
    final color = _tileColor(product);
    final price = double.tryParse('${product['sale_price']}'.replaceAll(',', '.')) ?? 0;
    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _addProduct(product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: color)),
                  if (_stockOf(product) != null)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                        child: Text('${_stockOf(product)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: const Color(0xFF111827),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _addProduct(product),
                        child: const SizedBox(
                          width: 28,
                          height: 28,
                          child: Icon(Icons.add, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MatchText(
                      text: '${product['name']}',
                      query: _search.text,
                      maxLines: 2,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.15, color: PosColors.ink),
                    ),
                    const Spacer(),
                    Text(
                      _money(price),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderPane(bool canPay) {
    final countLabel = _articleCount <= 1 ? '$_articleCount article' : '$_articleCount articles';
    return Container(
      width: 380,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: PosColors.line)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Commande', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      Text(countLabel, style: const TextStyle(color: PosColors.muted, fontSize: 13)),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _cart.isEmpty ? null : () => setState(() => _cart.clear()),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Vider'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: PosColors.danger,
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _typeChip('dine_in', 'Sur place'),
                const SizedBox(width: 6),
                _typeChip('takeaway', 'À emporter'),
                if (_deliveryEnabled) ...[
                  const SizedBox(width: 6),
                  _typeChip('delivery', 'Livraison'),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _cart.isEmpty
                ? const Center(child: Text('Panier vide', style: TextStyle(color: PosColors.muted)))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _cart.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) => _cartTile(index),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('Total à payer', style: TextStyle(color: PosColors.muted, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(_money(_payable), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                  ],
                ),
                if (_orderType == 'delivery' && _zoneFee > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Dont livraison ${_money(_zoneFee)}',
                      textAlign: TextAlign.end,
                      style: const TextStyle(color: PosColors.muted, fontSize: 12),
                    ),
                  ),
                if (_orderType == 'delivery') ...[
                  const SizedBox(height: 8),
                  _deliveryCard(),
                ],
                const SizedBox(height: 10),
                Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: PosColors.line),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final value = await showPosTextPad(
                        context,
                        title: 'Note cuisine',
                        initial: _kitchenNote.text,
                        hint: 'Message pour le cuisinier sur le ticket',
                      );
                      if (value == null) return;
                      _kitchenNote.text = value;
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Note cuisine', style: TextStyle(fontSize: 12, color: PosColors.muted, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            _kitchenNote.text.isEmpty ? 'Message pour le cuisinier sur le ticket' : _kitchenNote.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _kitchenNote.text.isEmpty ? PosColors.muted : PosColors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: PosColors.danger)),
                ],
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: canPay ? _encaisser : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE6B325),
                    disabledBackgroundColor: const Color(0xFFF6E7C3),
                    foregroundColor: const Color(0xFF3F2E05),
                    disabledForegroundColor: const Color(0xFFB7A57A),
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(_loading ? '…' : 'Encaisser', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeChip(String value, String label) {
    final selected = _orderType == value;
    return Expanded(
      child: Material(
        color: selected ? const Color(0xFF111827) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () async {
            setState(() => _orderType = value);
            if (value == 'delivery' && _zones.isEmpty) await _loadZones();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : PosColors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editDelivery() async {
    if (_zones.isEmpty) await _loadZones();
    if (!mounted) return;
    final draft = await showDeliveryWizard(
      context,
      name: _customerName.text,
      phone: _customerPhone.text,
      address: _deliveryAddress.text,
      notes: _deliveryNotes.text,
      zones: _zones,
      zoneId: _zoneId,
      requirePhone: _settingOn('delivery.require_phone'),
      requireZone: _settingOn('delivery.require_zone') || _zones.isNotEmpty,
    );
    if (draft == null) return;
    setState(() {
      _customerName.text = draft.name;
      _customerPhone.text = draft.phone;
      _deliveryAddress.text = draft.address;
      _deliveryNotes.text = draft.notes;
      _zoneId = draft.zoneId;
    });
  }

  Widget _deliveryCard() {
    final ready = _customerName.text.trim().isNotEmpty;
    final zone = _zoneName.isEmpty ? 'Zone' : '$_zoneName · ${_money(_zoneFee)}';
    final detail = ready
        ? '${_customerName.text.trim()}${_customerPhone.text.trim().isEmpty ? '' : ' · ${_customerPhone.text.trim()}'}'
        : 'Nom, téléphone, adresse';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: PosColors.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _editDelivery,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Livraison', style: TextStyle(fontSize: 12, color: PosColors.muted, fontWeight: FontWeight.w700)),
                Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  _deliveryAddress.text.trim().isEmpty ? zone : '${_deliveryAddress.text.trim()} · $zone',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: PosColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cartTile(int index) {
    final line = _cart[index];
    final qty = line.quantity == line.quantity.roundToDouble()
        ? '${line.quantity.round()}'
        : line.quantity.toStringAsFixed(2);
    final initial = line.name.trim().isEmpty ? '?' : line.name.trim()[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: line.color,
            child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(line.displayName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (!line.measured)
          _roundButton(
            icon: Icons.remove,
            onPressed: () => setState(() {
              line.quantity -= 1;
              if (line.quantity <= 0) _cart.removeAt(index);
            }),
          ),
          SizedBox(
            width: 22,
            child: Text(qty, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          if (!line.measured) _roundButton(icon: Icons.add, onPressed: () => setState(() => line.quantity += 1)),
          const SizedBox(width: 6),
          SizedBox(
            width: 78,
            child: Text(_money(line.lineTotal), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _cart.removeAt(index)),
            icon: const Icon(Icons.close, color: PosColors.danger, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _roundButton({required IconData icon, required VoidCallback onPressed}) {
    return Material(
      color: const Color(0xFFF3F4F6),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(width: 28, height: 28, child: Icon(icon, size: 16)),
      ),
    );
  }
}

class _ReceiptDialog extends StatelessWidget {
  const _ReceiptDialog({
    required this.order,
    required this.fallbackLines,
    required this.fallbackTotal,
    required this.footer,
    required this.logoUrl,
    required this.businessName,
    required this.offline,
  });

  final Map<String, dynamic>? order;
  final List<Map<String, dynamic>> fallbackLines;
  final String fallbackTotal;
  final String footer;
  final String logoUrl;
  final String businessName;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final business = order?['business'] is Map ? Map<String, dynamic>.from(order!['business'] as Map) : const <String, dynamic>{};
    final items = order?['items'] is List ? order!['items'] as List : fallbackLines;
    final total = order?['total'] ?? fallbackTotal;
    final shownFooter = '${business['footer'] ?? footer}';
    final shownLogo = '${business['logo_url'] ?? logoUrl}';
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (shownLogo.isNotEmpty)
              Image.network(shownLogo, height: 56, errorBuilder: (context, error, stack) => const SizedBox.shrink()),
            Text('${business['name'] ?? businessName}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            Text(offline ? 'Vente enregistrée hors ligne. Elle partira au retour du réseau.' : '${order?['public_ref'] ?? ''}'),
            const Divider(),
            for (final raw in items)
              if (raw is Map)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(child: Text('${raw['quantity']} × ${raw['name']}')),
                      Text('${raw['line_total']}'),
                    ],
                  ),
                ),
            if (order?['tax_enabled'] == true) Text('TVA incluse ${order?['tax_total'] ?? ''}'),
            const SizedBox(height: 8),
            Text('Total $total', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            if (shownFooter.trim().isNotEmpty) Text(shownFooter, style: const TextStyle(color: PosColors.muted)),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Nouvelle vente')),
          ],
        ),
      ),
    );
  }
}

