import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../providers/app_providers.dart';
import '../theme/pos_theme.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  String? _error;
  bool _busy = false;

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
    try {
      final response = await ref.read(dioProvider).get('/api/v1/orders');
      setState(() => _orders = apiList(response.data));
    } on DioException catch (error) {
      setState(() => _error = apiMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Map<String, dynamic> order) async {
    final id = order['id'] ?? order['public_ref'];
    try {
      final response = await ref.read(dioProvider).get('/api/v1/orders/$id');
      if (!mounted) return;
      final data = apiMap(response.data);
      await showDialog<void>(
        context: context,
        builder: (context) => _TicketDialog(
          order: data.isEmpty ? order : data,
          onPrint: () => _reprint(data.isEmpty ? order : data),
        ),
      );
    } on DioException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiMessage(error))));
    }
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
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(_error!, style: const TextStyle(color: PosColors.danger)),
          ),
        Expanded(child: _orders.isEmpty
            ? const Center(child: Text('Aucune commande', style: TextStyle(color: PosColors.muted)))
            : _list()),
      ],
    );
  }

  Widget _list() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _orders.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final order = _orders[index];
          return Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              onTap: () => _open(order),
              title: Text('${order['public_ref'] ?? order['id']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${order['sold_at'] ?? ''} · ${order['type'] ?? ''} · ${order['payment_method'] ?? ''}'),
              trailing: Text('${order['total'] ?? ''} ${order['currency'] ?? 'DH'}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          );
        },
      ),
    );
  }
}

class _TicketDialog extends StatelessWidget {
  const _TicketDialog({required this.order, required this.onPrint});

  final Map<String, dynamic> order;
  final VoidCallback onPrint;

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
