import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../l10n/caisse_text.dart';
import '../providers/app_providers.dart';
import '../theme/pos_theme.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  static const _periods = ['today', 'yesterday', 'week', 'month', 'last_30', 'custom'];
  String _period = 'today';
  DateTime? _from;
  DateTime? _to;
  Map<String, dynamic> _data = {};
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
      final response = await ref.read(dioProvider).get('/api/v1/dashboard', queryParameters: {
        'period': _period,
        if (_period == 'custom' && _from != null) 'from': _day(_from!),
        if (_period == 'custom' && _to != null) 'to': _day(_to!),
      });
      setState(() => _data = apiMap(response.data).isEmpty && response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : apiMap(response.data));
    } on DioException catch (error) {
      setState(() => _error = apiMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _day(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  Future<void> _pickCustom() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _from != null && _to != null ? DateTimeRange(start: _from!, end: _to!) : null,
    );
    if (range == null) return;
    setState(() {
      _period = 'custom';
      _from = range.start;
      _to = range.end;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final code = ref.watch(localeCodeProvider);
    final cash = _data['cash_session'] is Map ? Map<String, dynamic>.from(_data['cash_session'] as Map) : const <String, dynamic>{};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final period in _periods)
              ChoiceChip(
                label: Text(tx(code, period)),
                selected: _period == period,
                onSelected: (_) {
                  if (period == 'custom') {
                    _pickCustom();
                    return;
                  }
                  setState(() => _period = period);
                  _load();
                },
              ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!, style: const TextStyle(color: PosColors.danger)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _card(tx(code, 'revenue'), _data['sales_total']),
            _card(tx(code, 'order_count'), _data['orders_count']),
            _card(tx(code, 'average'), _data['average_order_value']),
            _card(tx(code, 'cash_pay'), _data['cash_total']),
            _card(tx(code, 'card_pay'), _data['card_total']),
            _card(tx(code, 'delivery'), _data['delivery_count']),
            _card(tx(code, 'expenses'), _data['expenses_total']),
            _card(tx(code, 'margin'), _data['estimated_gross_profit']),
            _card(tx(code, 'result'), _data['net_operating_result']),
          ],
        ),
        const SizedBox(height: 16),
        Text(tx(code, 'cash'), style: const TextStyle(fontWeight: FontWeight.w800)),
        Text(cash['open'] == true ? '${tx(code, 'expected')} ${cash['expected'] ?? ''}' : '—'),
        const SizedBox(height: 12),
        _namedList(tx(code, 'best'), _data['best_sellers']),
        _namedList(tx(code, 'recent'), _data['recent_orders']),
        _namedList(tx(code, 'low_stock'), _data['low_stock_products']),
        _namedList(tx(code, 'revenue'), _data['sales_over_time']),
        _namedList(tx(code, 'payment'), _data['sales_by_payment_method']),
        _namedList(tx(code, 'categories'), _data['sales_by_category']),
        _namedList(tx(code, 'result'), _data['revenue_vs_expenses']),
      ],
    );
  }

  Widget _card(String label, dynamic value) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: PosColors.muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text('${value ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _namedList(String title, dynamic raw) {
    final items = raw is List ? raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList() : const <Map<String, dynamic>>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        for (final item in items.take(8))
          Text(_line(item), style: const TextStyle(color: PosColors.muted)),
      ],
    );
  }

  String _line(Map<String, dynamic> item) {
    final label = item['name'] ?? item['label'] ?? item['category_name'] ?? item['method'] ?? item['public_ref'] ?? item['bucket'] ?? '';
    final value = item['total'] ?? item['total_sum'] ?? item['quantity_sum'] ?? item['sales'] ?? item['stock_quantity'] ?? '';
    return '$label  $value';
  }
}
