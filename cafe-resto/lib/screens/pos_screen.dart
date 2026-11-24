import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../providers/app_providers.dart';
import '../theme/pos_theme.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key, this.onCheckoutDone});

  final Future<void> Function()? onCheckoutDone;

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _CartLine {
  _CartLine({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
  });

  final int productId;
  final String name;
  final double unitPrice;
  double quantity;

  double get lineTotal => unitPrice * quantity;
}

class _PosScreenState extends ConsumerState<PosScreen> {
  List<dynamic> _catalog = [];
  Map<String, dynamic> _settings = {};
  Map<String, dynamic> _cash = {};
  String? _category;
  final List<_CartLine> _cart = [];
  String _orderType = 'dine_in';
  String _payment = 'cash';
  final _tendered = TextEditingController();
  final _kitchenNote = TextEditingController();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sync = ref.read(syncServiceProvider);
    final catalog = await sync.catalog();
    final settings = await sync.settings();
    final cash = await sync.cashStatus();
    setState(() {
      _catalog = catalog;
      _settings = settings;
      _cash = cash;
      _orderType = '${settings['pos.default_order_type'] ?? 'dine_in'}';
      _payment = '${settings['pos.default_payment_method'] ?? 'cash'}';
      _loading = false;
    });
  }

  List<String> get _categories {
    final names = <String>{};
    for (final item in _catalog) {
      final map = Map<String, dynamic>.from(item as Map);
      names.add('${map['category_name'] ?? 'Autres'}');
    }
    final list = names.toList()..sort();
    return list;
  }

  List<Map<String, dynamic>> get _products {
    return _catalog
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((p) => _category == null || '${p['category_name']}' == _category)
        .toList();
  }

  double get _total => _cart.fold(0, (sum, line) => sum + line.lineTotal);

  bool get _salesBlocked {
    final require = _cash['require_open_session'] == true;
    final open = _cash['session_open'] == true;
    return require && !open;
  }

  void _addProduct(Map<String, dynamic> product) {
    final id = product['id'] as int;
    final existing = _cart.where((l) => l.productId == id).toList();
    if (existing.isNotEmpty) {
      setState(() => existing.first.quantity += 1);
      return;
    }
    setState(() {
      _cart.add(
        _CartLine(
          productId: id,
          name: '${product['name']}',
          unitPrice: double.tryParse('${product['sale_price']}') ?? 0,
          quantity: 1,
        ),
      );
    });
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty || _salesBlocked) {
      setState(() => _error = _salesBlocked ? 'Ouvrez le tiroir pour vendre.' : 'Panier vide.');
      return;
    }

    final tendered = _payment == 'cash'
        ? double.tryParse(_tendered.text.replaceAll(',', '.'))
        : _total;
    if (_payment == 'cash' && (tendered == null || tendered < _total)) {
      setState(() => _error = 'Montant reçu insuffisant.');
      return;
    }

    setState(() {
      _error = null;
      _loading = true;
    });

    final online = ref.read(onlineProvider).valueOrNull ?? true;
    final key = const Uuid().v4();
    final payload = {
      'type': _orderType,
      'payment_method': _payment,
      if (_payment == 'cash') 'tendered': tendered,
      'kitchen_note': _kitchenNote.text.trim().isEmpty ? null : _kitchenNote.text.trim(),
      'lines': _cart
          .map(
            (l) => {
              'product_id': l.productId,
              'quantity': l.quantity,
              'modifiers': <int>[],
            },
          )
          .toList(),
      'client_created_at': DateTime.now().toUtc().toIso8601String(),
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
              'name': l.name,
              'quantity': l.quantity,
              'line_total': l.lineTotal.toStringAsFixed(2),
            },
          )
          .toList();
      final totalStr = _total.toStringAsFixed(2);
      final note = _kitchenNote.text.trim();

      String publicRef = result['offline'] == true ? 'OFF-$key'.substring(0, 12) : 'TICKET';
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
            );
      } catch (_) {
        // Impression best-effort.
      }

      setState(() {
        _cart.clear();
        _kitchenNote.clear();
        _tendered.clear();
      });
      await widget.onCheckoutDone?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['offline'] == true
                ? 'Vente enregistrée hors-ligne (sync plus tard)'
                : 'Vente encaissée',
          ),
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

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_salesBlocked)
                MaterialBanner(
                  content: const Text('Tiroir fermé — ouvrez une session pour vendre.'),
                  backgroundColor: const Color(0xFFFFEDD5),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        try {
                          await ref.read(syncServiceProvider).refreshCashStatus();
                          final cash = await ref.read(syncServiceProvider).cashStatus();
                          setState(() => _cash = cash);
                        } catch (_) {}
                      },
                      child: const Text('Rafraîchir'),
                    ),
                  ],
                ),
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('Tous'),
                        selected: _category == null,
                        onSelected: (_) => setState(() => _category = null),
                      ),
                    ),
                    ..._categories.map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 1.1,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _products.length,
                  itemBuilder: (context, index) {
                    final product = _products[index];
                    return InkWell(
                      onTap: _salesBlocked ? null : () => _addProduct(product),
                      borderRadius: BorderRadius.circular(14),
                      child: Ink(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: PosColors.line),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  '${product['name']}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Text(
                                '${product['sale_price']}',
                                style: const TextStyle(
                                  color: PosColors.accent,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 340,
          color: Colors.white,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    for (final type in ['dine_in', 'takeaway', 'delivery'])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: ChoiceChip(
                            label: Text(
                              type == 'dine_in'
                                  ? 'Place'
                                  : type == 'takeaway'
                                      ? 'Emporter'
                                      : 'Livr.',
                              style: const TextStyle(fontSize: 11),
                            ),
                            selected: _orderType == type,
                            onSelected: (_) => setState(() => _orderType = type),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _cart.isEmpty
                    ? const Center(child: Text('Panier vide', style: TextStyle(color: PosColors.muted)))
                    : ListView.builder(
                        itemCount: _cart.length,
                        itemBuilder: (context, index) {
                          final line = _cart[index];
                          return ListTile(
                            dense: true,
                            title: Text(line.name),
                            subtitle: Text('${line.quantity} × ${line.unitPrice.toStringAsFixed(2)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () => setState(() {
                                    line.quantity -= 1;
                                    if (line.quantity <= 0) {
                                      _cart.removeAt(index);
                                    }
                                  }),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () => setState(() => line.quantity += 1),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: _kitchenNote,
                  decoration: const InputDecoration(
                    labelText: 'Note cuisine',
                    isDense: true,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Espèces'),
                          selected: _payment == 'cash',
                          onSelected: (_) => setState(() => _payment = 'cash'),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Carte'),
                          selected: _payment == 'card',
                          onSelected: (_) => setState(() => _payment = 'card'),
                        ),
                      ],
                    ),
                    if (_payment == 'cash') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _tendered,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Reçu',
                          isDense: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Total ${_total.toStringAsFixed(2)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    if (_error != null)
                      Text(_error!, style: const TextStyle(color: PosColors.danger)),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _loading ? null : _checkout,
                      child: Text(_loading ? '…' : 'Encaisser'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
