import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../auth/staff_user.dart';
import '../db/list_cache.dart';
import '../providers/app_providers.dart';
import '../theme/pos_theme.dart';
import '../widgets/match_text.dart';
import '../widgets/status_chip.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key, this.user = StaffUser.empty});

  final StaffUser user;

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  String? _error;
  bool _busy = false;
  bool _fromCache = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = ref.read(localStoreProvider);
    final cached = await loadList(store, 'orders_cache');
    try {
      final response = await ref.read(dioProvider).get('/api/v1/orders');
      final rows = apiList(response.data);
      await saveList(store, 'orders_cache', rows);
      setState(() {
        _orders = rows;
        _fromCache = false;
      });
    } on DioException catch (error) {
      setState(() {
        if (cached.isNotEmpty) {
          _orders = cached;
          _fromCache = true;
          _error = null;
        } else {
          _error = cached.isEmpty ? 'Pas encore synchronisé' : apiMessage(error);
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int? _orderId(Map<String, dynamic> order) => int.tryParse('${order['id']}');

  Future<void> _open(Map<String, dynamic> order) async {
    final id = _orderId(order);
    final online = ref.read(onlineProvider).valueOrNull ?? false;
    if (id == null || !online) {
      await _showTicket(order);
      return;
    }
    try {
      final response = await ref.read(dioProvider).get('/api/v1/orders/$id');
      if (!mounted) return;
      final data = apiMap(response.data);
      await _showTicket(data.isEmpty ? order : data);
    } on DioException catch (error) {
      if (!mounted) return;
      if (error.response?.statusCode == 404) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cette commande n’existe pas sur le serveur.')),
        );
        await _showTicket(order);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiMessage(error))));
    }
  }

  Future<void> _showTicket(Map<String, dynamic> order) {
    return showDialog<void>(
      context: context,
      builder: (context) => _TicketDialog(
        order: order,
        onPrint: () => _reprint(order),
        canChange: _orderId(order) != null && (widget.user.can('orders.update') || widget.user.can('orders.manage')),
        canCancel: _orderId(order) != null && (widget.user.can('orders.cancel') || widget.user.can('orders.manage')),
        onChange: () => _change(order),
        onCancel: () => _cancel(order),
      ),
    );
  }

  Future<void> _reprint(Map<String, dynamic> order) async {
    final settings = await ref.read(syncServiceProvider).settings();
    final items = order['items'] is List ? order['items'] as List : const [];
    final lines = <Map<String, dynamic>>[
      for (final raw in items)
        if (raw is Map)
          {
            'name': raw['name'],
            'quantity': raw['quantity'],
            'line_total': raw['line_total'],
          },
    ];
    await ref.read(printServiceProvider).printSale(
          settings: settings,
          publicRef: '${order['public_ref'] ?? order['id'] ?? ''}',
          cartLines: lines,
          total: '${order['total'] ?? ''}',
          orderType: '${order['type'] ?? ''}',
          kitchen: false,
          openDrawer: false,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ticket renvoyé à l’imprimante.')));
  }

  Future<void> _change(Map<String, dynamic> order) async {
    final id = _orderId(order);
    if (id == null) return;
    final items = order['items'] is List ? order['items'] as List : const [];
    final lines = <Map<String, dynamic>>[
      for (final raw in items)
        if (raw is Map && raw['product_id'] != null)
          {
            'product_id': raw['product_id'],
            'quantity': raw['quantity'],
            'modifiers': raw['modifiers'] ?? [],
          },
    ];
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cette vente ne peut pas être modifiée depuis la tablette.')));
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Modifier la vente'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final line in lines)
                Row(
                  children: [
                    Expanded(child: Text('Produit ${line['product_id']}')),
                    IconButton(onPressed: () => setLocal(() => line['quantity'] = (num.tryParse('${line['quantity']}') ?? 1) - 1), icon: const Icon(Icons.remove)),
                    Text('${line['quantity']}'),
                    IconButton(onPressed: () => setLocal(() => line['quantity'] = (num.tryParse('${line['quantity']}') ?? 0) + 1), icon: const Icon(Icons.add)),
                  ],
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Envoyer')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await _sendOrderOp(orderId: '$id', op: 'sale_update', body: {
      'lines': lines.where((line) => (num.tryParse('${line['quantity']}') ?? 0) > 0).toList(),
      'payment_method': order['payment_method'] ?? 'cash',
    }, waiting: 'Modification en attente. Elle partira au retour du réseau.');
  }

  Future<void> _cancel(Map<String, dynamic> order) async {
    final id = _orderId(order);
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler la vente'),
        content: const Text('La vente sera annulée sur le serveur. Ce n’est pas un simple oubli local.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Retour')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Annuler la vente')),
        ],
      ),
    );
    if (ok != true) return;
    await _sendOrderOp(orderId: '$id', op: 'sale_cancel', body: {'reason': 'Annulée depuis la caisse'}, waiting: 'Annulation en attente. Elle partira au retour du réseau.');
  }

  Future<void> _sendOrderOp({
    required String orderId,
    required String op,
    required Map<String, dynamic> body,
    required String waiting,
  }) async {
    final online = ref.read(onlineProvider).valueOrNull ?? false;
    final key = const Uuid().v4();
    if (!online) {
      await ref.read(orderQueueProvider).enqueueOperation(key, {'_op': op, '_order_id': orderId, ...body});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(waiting)));
      return;
    }
    try {
      final path = op == 'sale_cancel' ? '/api/v1/orders/$orderId/cancel' : '/api/v1/orders/$orderId/changes';
      await ref.read(dioProvider).post(path, data: body, options: Options(headers: {'Idempotency-Key': key}));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Opération enregistrée.')));
      await _load();
    } on DioException catch (error) {
      if (error.response?.statusCode == 404 || error.response?.statusCode == 405) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Le serveur ne permet pas encore cette opération.')));
        return;
      }
      if (error.type == DioExceptionType.connectionError || error.type == DioExceptionType.connectionTimeout) {
        await ref.read(orderQueueProvider).enqueueOperation(key, {'_op': op, '_order_id': orderId, ...body});
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(waiting)));
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              const Text('Commandes', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
              const Spacer(),
              TextButton(onPressed: _busy ? null : _load, child: const Text('Actualiser')),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final field = TextEditingController(text: _query);
                final value = await showDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Recherche'),
                    content: TextField(
                      controller: field,
                      decoration: const InputDecoration(hintText: 'Code commande, client, téléphone…'),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Effacer')),
                      FilledButton(onPressed: () => Navigator.pop(context, field.text), child: const Text('Chercher')),
                    ],
                  ),
                );
                if (value == null || !mounted) return;
                setState(() => _query = value.trim());
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: PosColors.muted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_query.isEmpty ? 'Code commande, client, téléphone…' : _query)),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_fromCache)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Liste enregistrée sur la tablette.', style: TextStyle(color: PosColors.accent, fontWeight: FontWeight.w700)),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(_error!, style: const TextStyle(color: PosColors.danger)),
          ),
        Expanded(child: _visible.isEmpty
            ? Center(child: Text(_emptyLabel, style: const TextStyle(color: PosColors.muted)))
            : _list()),
      ],
    );
  }

  List<Map<String, dynamic>> get _visible {
    return _orders.where((order) => rowMatches(order, _query, const ['public_ref', 'id', 'customer_name', 'customer_phone', 'type'])).toList();
  }

  String get _emptyLabel {
    if (_query.isNotEmpty) return 'Aucun résultat';
    if (_orders.isEmpty && _error != null) return 'Pas encore synchronisé';
    return 'Aucune commande';
  }

  StatusTone _tone(Map<String, dynamic> order) {
    return switch ('${order['status'] ?? order['type']}') {
      'cancelled' => StatusTone.cancelled,
      'paid' => StatusTone.paid,
      'pending' => StatusTone.waiting,
      'delivery' => StatusTone.assigned,
      'takeaway' => StatusTone.progress,
      _ => StatusTone.delivered,
    };
  }

  Widget _list() {
    final rows = _visible;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final order = rows[index];
          final ref = '${order['public_ref'] ?? order['id']}';
          return Material(
            color: index.isOdd ? const Color(0xFFF8FAFC) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: PosColors.line),
            ),
            child: ListTile(
              onTap: () => _open(order),
              title: MatchText(text: ref, query: _query, style: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'monospace')),
              subtitle: Text('${order['sold_at'] ?? ''} · ${order['type'] ?? ''} · ${order['payment_method'] ?? ''}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusChip(label: _chipLabel(order), tone: _tone(order)),
                  const SizedBox(width: 8),
                  Text('${order['total'] ?? ''} ${order['currency'] ?? 'DH'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _chipLabel(Map<String, dynamic> order) {
    return switch ('${order['status'] ?? ''}') {
      'cancelled' => 'Annulée',
      'paid' => 'Payée',
      'pending' => 'En attente',
      _ => switch ('${order['type']}') {
          'delivery' => 'Livraison',
          'takeaway' => 'Emporter',
          _ => 'Sur place',
        },
    };
  }
}

class _TicketDialog extends StatelessWidget {
  const _TicketDialog({
    required this.order,
    required this.onPrint,
    required this.canChange,
    required this.canCancel,
    required this.onChange,
    required this.onCancel,
  });

  final Map<String, dynamic> order;
  final VoidCallback onPrint;
  final bool canChange;
  final bool canCancel;
  final VoidCallback onChange;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final business = order['business'] is Map ? Map<String, dynamic>.from(order['business'] as Map) : const <String, dynamic>{};
    final items = order['items'] is List ? order['items'] as List : const [];
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('${business['name'] ?? 'Ticket'}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text('${order['public_ref'] ?? ''} · ${order['sold_at'] ?? ''}'),
            const Divider(),
            for (final raw in items)
              if (raw is Map)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text('${raw['quantity']} × ${raw['name']}')),
                      Text('${raw['line_total']}'),
                    ],
                  ),
                ),
            const Divider(),
            if (order['tax_enabled'] == true) Text('TVA ${order['tax_rate'] ?? ''} : ${order['tax_total'] ?? ''}'),
            Text('Total ${order['total'] ?? ''} ${order['currency'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            if ('${business['footer'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${business['footer']}', style: const TextStyle(color: PosColors.muted)),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(onPressed: onPrint, child: const Text('Réimprimer')),
                  if (canChange) OutlinedButton(onPressed: onChange, child: const Text('Modifier')),
                  if (canCancel) OutlinedButton(onPressed: onCancel, child: const Text('Annuler la vente')),
                  FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
