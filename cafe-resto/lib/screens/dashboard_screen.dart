import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../l10n/caisse_text.dart';
import '../providers/app_providers.dart';
import '../theme/pos_theme.dart';
import '../widgets/status_chip.dart';

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
  bool _fromCache = false;

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
    Map<String, dynamic> cached = {};
    try {
      final raw = await store.getJson('dashboard_$_period');
      if (raw is Map) cached = Map<String, dynamic>.from(raw);
    } catch (_) {}
    try {
      final response = await ref.read(dioProvider).get('/api/v1/dashboard', queryParameters: {
        'period': _period,
        if (_period == 'custom' && _from != null) 'from': _day(_from!),
        if (_period == 'custom' && _to != null) 'to': _day(_to!),
      });
      final data = apiMap(response.data).isEmpty && response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : apiMap(response.data);
      try {
        await store.putJson('dashboard_$_period', data);
      } catch (_) {}
      setState(() {
        _data = data;
        _fromCache = false;
      });
    } on DioException catch (error) {
      setState(() {
        if (cached.isNotEmpty) {
          _data = cached;
          _fromCache = true;
          _error = null;
        } else {
          _error = apiMessage(error);
        }
      });
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
        if (_fromCache)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Chiffres enregistrés sur la tablette.', style: TextStyle(color: PosColors.accent, fontWeight: FontWeight.w700)),
          ),
        if (_error != null) Text(_error!, style: const TextStyle(color: PosColors.danger)),
        const SizedBox(height: 16),
        _section('Ventes', PosColors.success, [
          _metric(tx(code, 'revenue'), _money(_data['sales_total']), PosColors.success),
          _metric(tx(code, 'order_count'), _plain(_data['orders_count']), PosColors.info),
          _metric(tx(code, 'average'), _money(_data['average_order_value']), PosColors.progress),
        ]),
        _section('Encaissements', PosColors.info, [
          _metric(tx(code, 'cash_pay'), _money(_data['cash_total']), PosColors.success),
          _metric(tx(code, 'card_pay'), _money(_data['card_total']), PosColors.info),
          _metric(tx(code, 'delivery'), _plain(_data['delivery_count']), PosColors.warning),
        ]),
        _section('Résultat', PosColors.paid, [
          _metric(tx(code, 'expenses'), _money(_data['expenses_total']), PosColors.danger),
          _metric(tx(code, 'margin'), _money(_data['estimated_gross_profit']), PosColors.paid),
          _metric(tx(code, 'result'), _money(_data['net_operating_result']), PosColors.accent),
        ]),
        const SizedBox(height: 8),
        _cashBand(code, cash),
        const SizedBox(height: 8),
        _table(tx(code, 'best'), _data['best_sellers'], PosColors.success),
        _table(tx(code, 'recent'), _data['recent_orders'], PosColors.info),
        _table(tx(code, 'low_stock'), _data['low_stock_products'], PosColors.danger),
        _table(tx(code, 'payment'), _data['sales_by_payment_method'], PosColors.progress),
        _table(tx(code, 'categories'), _data['sales_by_category'], PosColors.warning),
      ],
    );
  }

  Widget _section(String title, Color color, List<Widget> metrics) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width > 720 ? 3 : 1;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final metric in metrics) SizedBox(width: (width - (columns - 1) * 8) / columns, child: metric),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: PosColors.muted, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: color)),
        ],
      ),
    );
  }

  Widget _cashBand(String code, Map<String, dynamic> cash) {
    final open = cash['open'] == true;
    final color = open ? PosColors.success : PosColors.muted;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          StatusChip(label: open ? 'Ouverte' : 'Fermée', tone: open ? StatusTone.open : StatusTone.closed),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              open ? '${tx(code, 'expected')} ${_money(cash['expected'])}' : tx(code, 'no_session'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _table(String title, dynamic raw, Color color) {
    final items = raw is List ? raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList() : const <Map<String, dynamic>>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PosColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          ),
          for (var i = 0; i < items.take(8).length; i++)
            Container(
              color: i.isOdd ? const Color(0xFFF8FAFC) : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(child: Text(_label(items[i]), style: const TextStyle(fontWeight: FontWeight.w700))),
                  Text(_value(items[i]), style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _money(dynamic value) {
    if (value == null || '$value'.isEmpty) return '—';
    final number = double.tryParse('$value'.replaceAll(',', '.'));
    if (number == null) return '$value';
    final parts = number.toStringAsFixed(2).split('.');
    return '${parts[0]},${parts[1]} DH';
  }

  String _plain(dynamic value) => value == null || '$value'.isEmpty ? '—' : '$value';

  String _label(Map<String, dynamic> item) {
    return '${item['name'] ?? item['label'] ?? item['category_name'] ?? item['method'] ?? item['public_ref'] ?? item['bucket'] ?? ''}';
  }

  String _value(Map<String, dynamic> item) {
    final value = item['total'] ?? item['total_sum'] ?? item['quantity_sum'] ?? item['sales'] ?? item['stock_quantity'] ?? '';
    return '$value';
  }

}
