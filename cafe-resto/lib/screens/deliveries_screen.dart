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
        for (final delivery in _items)
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
