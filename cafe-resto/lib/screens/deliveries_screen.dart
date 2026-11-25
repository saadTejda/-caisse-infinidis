import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../auth/staff_user.dart';
import '../theme/pos_theme.dart';
import 'pos_dialogs.dart';

class DeliveriesScreen extends ConsumerStatefulWidget {
  const DeliveriesScreen({super.key, required this.user});

  final StaffUser user;

  @override
  ConsumerState<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends ConsumerState<DeliveriesScreen> {
  static const _statuses = ['pending', 'assigned', 'picked_up', 'out_for_delivery', 'delivered', 'cancelled'];
  static const _statusLabels = {
    'pending': 'En attente',
    'assigned': 'Assignée',
    'picked_up': 'Récupérée',
    'out_for_delivery': 'En route',
    'delivered': 'Livrée',
    'cancelled': 'Annulée',
  };
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _zones = [];
  String? _error;
  bool _busy = false;
  String _filter = 'waiting';

  bool get _manage => widget.user.can('delivery.manage');

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
      final dio = ref.read(dioProvider);
      final deliveries = await dio.get('/api/v1/deliveries');
      final zones = await dio.get('/api/v1/delivery-zones');
      setState(() {
        _items = apiList(deliveries.data);
        _zones = apiList(zones.data);
      });
    } on DioException catch (error) {
      setState(() => _error = apiMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _status(Map<String, dynamic> delivery, String status) async {
    var note = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(_statusLabels[status] ?? status),
          content: ListTile(
            title: const Text('Note'),
            subtitle: Text(note.isEmpty ? 'Optionnelle' : note),
            onTap: () async {
              final value = await showPosTextPad(context, title: 'Note', initial: note, hint: 'Optionnelle');
              if (value != null) setLocal(() => note = value);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmer')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(dioProvider).post('/api/v1/deliveries/${delivery['id']}/status', data: {
        'status': status,
        if (note.trim().isNotEmpty) 'note': note.trim(),
      });
      await _load();
    } on DioException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiMessage(error))));
    }
  }

  Future<void> _assign(Map<String, dynamic> delivery) async {
    try {
      final response = await ref.read(dioProvider).get('/api/v1/deliveries/drivers');
      final drivers = apiList(response.data);
      if (!mounted) return;
      final driverId = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Livreur'),
          children: [
            for (final driver in drivers)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, int.tryParse('${driver['id']}')),
                child: Text('${driver['name']}'),
              ),
          ],
        ),
      );
      if (driverId == null) return;
      await ref.read(dioProvider).post('/api/v1/deliveries/${delivery['id']}/assign', data: {'driver_id': driverId});
      await _load();
    } on DioException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiMessage(error))));
    }
  }

  bool _unassigned(Map<String, dynamic> delivery) {
    final driver = delivery['driver_id'] ?? delivery['driver'];
    return driver == null || '$driver'.isEmpty;
  }

  num _amount(Map<String, dynamic> delivery) {
    final order = delivery['order'];
    final raw = order is Map
        ? (order['total'] ?? order['grand_total'] ?? order['amount_due'])
        : (delivery['total'] ?? delivery['amount_due'] ?? delivery['cod_amount'] ?? delivery['fee']);
    return num.tryParse('$raw'.replaceAll(',', '.')) ?? 0;
  }

  bool _settled(Map<String, dynamic> delivery) {
    final status = '${delivery['payment_status'] ?? delivery['settlement_status'] ?? ''}';
    return delivery['settled_at'] != null || delivery['driver_paid_at'] != null || delivery['is_paid'] == true || status == 'paid';
  }

  List<Map<String, dynamic>> get _visible {
    final items = _items.where((delivery) {
      final status = '${delivery['status']}';
      switch (_filter) {
        case 'waiting':
          return _unassigned(delivery) && status != 'cancelled' && status != 'delivered';
        case 'route':
          return status == 'assigned' || status == 'picked_up' || status == 'out_for_delivery';
        case 'done':
          return status == 'delivered';
        default:
          return status != 'cancelled';
      }
    }).toList();
    items.sort((a, b) {
      final rankA = _unassigned(a) ? 0 : 1;
      final rankB = _unassigned(b) ? 0 : 1;
      return rankA.compareTo(rankB);
    });
    return items;
  }

  List<Widget> _driverTotals() {
    final delivered = _items.where((delivery) => '${delivery['status']}' == 'delivered').toList();
    final byDriver = <String, List<Map<String, dynamic>>>{};
    for (final delivery in delivered) {
      final driver = delivery['driver'];
      final name = driver is Map ? '${driver['name'] ?? 'Livreur'}' : '${delivery['driver_name'] ?? 'Non assigné'}';
      byDriver.putIfAbsent(name, () => []).add(delivery);
    }
    if (byDriver.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      const Text('À encaisser des livreurs', style: TextStyle(fontWeight: FontWeight.w800)),
      for (final entry in byDriver.entries)
        ListTile(
          dense: true,
          title: Text(entry.key),
          subtitle: Text('${entry.value.length} livrée(s) · ${entry.value.where((item) => !_settled(item)).length} à payer'),
          trailing: Text(
            posMoney(entry.value.where((item) => !_settled(item)).fold<num>(0, (sum, item) => sum + _amount(item)).toDouble()),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
    ];
  }

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    await launchUrl(uri);
  }

  Future<void> _editZone([Map<String, dynamic>? zone]) async {
    final name = TextEditingController(text: '${zone?['name'] ?? ''}');
    final fee = TextEditingController(text: '${zone?['fee'] ?? '0'}');
    final minimum = TextEditingController(text: '${zone?['min_order'] ?? '0'}');
    var active = zone?['is_active'] != false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(zone == null ? 'Zone' : '${zone['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom')),
            TextField(controller: fee, decoration: const InputDecoration(labelText: 'Frais')),
            TextField(controller: minimum, decoration: const InputDecoration(labelText: 'Minimum')),
            StatefulBuilder(
              builder: (context, setLocal) => SwitchListTile(
                value: active,
                title: const Text('Active'),
                onChanged: (value) => setLocal(() => active = value),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (saved != true) return;
    final body = {
      'name': name.text.trim(),
      'fee': double.tryParse(fee.text.replaceAll(',', '.')) ?? 0,
      'min_order': double.tryParse(minimum.text.replaceAll(',', '.')) ?? 0,
      'is_active': active,
    };
    try {
      final dio = ref.read(dioProvider);
      if (zone == null) {
        await dio.post('/api/v1/delivery-zones', data: body);
      } else {
        await dio.patch('/api/v1/delivery-zones/${zone['id']}', data: body);
      }
      await _load();
    } on DioException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null) Text(_error!, style: const TextStyle(color: PosColors.danger)),
        if (_busy) const LinearProgressIndicator(),
        if (_manage)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => _editZone(), icon: const Icon(Icons.add), label: const Text('Zone')),
          ),
        if (_manage)
          for (final zone in _zones)
            ListTile(
              title: Text('${zone['name']} · ${posMoney(double.tryParse('${zone['fee']}') ?? 0)}'),
              subtitle: Text('min ${zone['min_order'] ?? 0} · ${zone['is_active'] == false ? 'arrêtée' : 'active'}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ref.read(dioProvider).delete('/api/v1/delivery-zones/${zone['id']}');
                    await _load();
                  } on DioException catch (error) {
                    if (!mounted) return;
                    messenger.showSnackBar(SnackBar(content: Text(apiMessage(error))));
                  }
                },
              ),
              onTap: () => _editZone(zone),
            ),
        const Divider(),
        Wrap(
          spacing: 6,
          children: [
            _filterChip('waiting', 'Non assignées'),
            _filterChip('route', 'En route'),
            _filterChip('done', 'Livrées'),
            _filterChip('all', 'Toutes'),
          ],
        ),
        if (_manage) ..._driverTotals(),
        const SizedBox(height: 8),
        for (final delivery in _visible)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${delivery['customer_name'] ?? ''} · ${_statusLabels['${delivery['status']}'] ?? delivery['status']}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text('${delivery['address'] ?? ''}'),
                  Text('${delivery['customer_phone'] ?? ''}'),
                  Wrap(
                    spacing: 6,
                    children: [
                      if ('${delivery['customer_phone'] ?? ''}'.isNotEmpty)
                        TextButton(onPressed: () => _call('${delivery['customer_phone']}'), child: const Text('Appeler')),
                      if (_manage) TextButton(onPressed: () => _assign(delivery), child: const Text('Assigner')),
                      for (final status in _statuses)
                        if (status != delivery['status'])
                          ActionChip(label: Text(_statusLabels[status] ?? status), onPressed: () => _status(delivery, status)),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
