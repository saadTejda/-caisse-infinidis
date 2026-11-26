import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../auth/staff_user.dart';
import '../db/list_cache.dart';
import '../providers/app_providers.dart';
import '../theme/pos_theme.dart';
import '../widgets/match_text.dart';
import '../widgets/status_chip.dart';
import 'pos_dialogs.dart';

class DeliveriesScreen extends ConsumerStatefulWidget {
  const DeliveriesScreen({super.key, required this.user});

  final StaffUser user;

  @override
  ConsumerState<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends ConsumerState<DeliveriesScreen> {
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
  List<Map<String, dynamic>> _drivers = [];
  String? _error;
  bool _busy = false;
  bool _fromCache = false;
  String _query = '';
  bool _showPaid = false;
  int _tab = 0;

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
    final store = ref.read(localStoreProvider);
    final cachedItems = await loadList(store, 'deliveries_cache');
    final cachedZones = await loadList(store, 'zones_cache');
    final cachedDrivers = await loadList(store, 'drivers_cache');
    try {
      final dio = ref.read(dioProvider);
      final deliveries = await dio.get('/api/v1/deliveries');
      final zones = await dio.get('/api/v1/delivery-zones');
      final rows = apiList(deliveries.data);
      final zoneRows = apiList(zones.data);
      await saveList(store, 'deliveries_cache', rows);
      await saveList(store, 'zones_cache', zoneRows);
      setState(() {
        _items = rows;
        _zones = zoneRows;
        _drivers = cachedDrivers;
        _fromCache = false;
      });
    } on DioException catch (error) {
      setState(() {
        _items = cachedItems;
        _zones = cachedZones;
        _drivers = cachedDrivers;
        _fromCache = cachedItems.isNotEmpty || cachedZones.isNotEmpty;
        _error = _fromCache ? null : apiMessage(error);
      });
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

  Future<List<Map<String, dynamic>>> _driverList() async {
    final store = ref.read(localStoreProvider);
    try {
      final response = await ref.read(dioProvider).get('/api/v1/deliveries/drivers');
      final drivers = apiList(response.data);
      await saveList(store, 'drivers_cache', drivers);
      _drivers = drivers;
      return drivers;
    } on DioException {
      if (_drivers.isNotEmpty) return _drivers;
      return loadList(store, 'drivers_cache');
    }
  }

  Future<void> _assign(Map<String, dynamic> delivery) async {
    final drivers = await _driverList();
    if (!mounted) return;
    if (drivers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Synchronisez les livreurs une fois en ligne.')));
      return;
    }
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
    Map<String, dynamic>? driver;
    for (final item in drivers) {
      if (int.tryParse('${item['id']}') == driverId) driver = item;
    }
    final online = ref.read(onlineProvider).valueOrNull ?? false;
    Future<void> park() async {
      await ref.read(orderQueueProvider).enqueueOperation(const Uuid().v4(), {
        '_op': 'delivery_assign',
        '_delivery_id': delivery['id'],
        'driver_id': driverId,
      });
      _patch(delivery, {
        'driver_id': driverId,
        'driver': driver ?? {'id': driverId, 'name': 'Livreur'},
        'status': 'assigned',
        '_local': true,
      });
    }
    if (!online) {
      await park();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assignation en attente. Elle partira au retour du réseau.')));
      return;
    }
    try {
      await ref.read(dioProvider).post('/api/v1/deliveries/${delivery['id']}/assign', data: {'driver_id': driverId});
      await _load();
    } on DioException catch (error) {
      if (!mounted) return;
      if (error.response?.statusCode == 409) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Déjà assigné sur le web. On aligne l’affichage.')));
        await _load();
        return;
      }
      if (_network(error)) {
        await park();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assignation en attente. Elle partira au retour du réseau.')));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiMessage(error))));
    }
  }

  bool _network(DioException error) {
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.unknown;
  }

  void _patch(Map<String, dynamic> delivery, Map<String, dynamic> changes) {
    setState(() {
      final index = _items.indexWhere((item) => item['id'] == delivery['id']);
      if (index < 0) return;
      _items[index] = {..._items[index], ...changes};
    });
    saveList(ref.read(localStoreProvider), 'deliveries_cache', _items);
  }

  Future<void> _markPaid(Map<String, dynamic> delivery) async {
    final amount = _amount(delivery);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marquer payé'),
        content: Text('${posMoney(amount)}\n${DateTime.now().toLocal()}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmer')),
        ],
      ),
    );
    if (ok != true) return;
    final body = {
      '_op': 'driver_payment',
      '_delivery_id': delivery['id'],
      'amount': amount,
      'paid_at': DateTime.now().toUtc().toIso8601String(),
      'note': null,
    };
    final online = ref.read(onlineProvider).valueOrNull ?? false;
    Future<void> park() async {
      await ref.read(orderQueueProvider).enqueueOperation(const Uuid().v4(), body);
      _patch(delivery, {'payment_status': 'paid', 'is_paid': true, 'driver_paid_at': body['paid_at'], '_local': true});
    }
    if (!online) {
      await park();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paiement en attente. Il partira au retour du réseau.')));
      return;
    }
    try {
      await ref.read(dioProvider).post('/api/v1/deliveries/${delivery['id']}/driver-payment', data: {
        'amount': amount,
        'paid_at': body['paid_at'],
        'note': null,
      }, options: Options(headers: {'Idempotency-Key': const Uuid().v4()}));
      await _load();
    } on DioException catch (error) {
      if (!mounted) return;
      final data = error.response?.data;
      final code = data is Map ? '${data['code']}' : '';
      if (error.response?.statusCode == 409 || code == 'already_paid') {
        _patch(delivery, {'payment_status': 'paid', 'is_paid': true, 'driver_paid_at': DateTime.now().toUtc().toIso8601String()});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Déjà payé sur le web. On aligne l’affichage.')));
        return;
      }
      if (error.response?.statusCode == 404 || error.response?.statusCode == 405) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Le serveur ne permet pas encore cette opération.')));
        return;
      }
      if (_network(error)) {
        await park();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paiement en attente. Il partira au retour du réseau.')));
        return;
      }
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

  List<Map<String, dynamic>> get _toAssign {
    return _items.where((delivery) {
      final status = '${delivery['status']}';
      return _unassigned(delivery) && status != 'cancelled' && status != 'delivered' && _matches(delivery);
    }).toList();
  }

  List<Map<String, dynamic>> get _onRoute {
    return _items.where((delivery) {
      final status = '${delivery['status']}';
      return (status == 'assigned' || status == 'picked_up' || status == 'out_for_delivery') && _matches(delivery);
    }).toList();
  }

  String? _nextStatus(String status) {
    return switch (status) {
      'assigned' => 'picked_up',
      'picked_up' => 'out_for_delivery',
      'out_for_delivery' => 'delivered',
      _ => null,
    };
  }

  List<Map<String, dynamic>> get _due {
    return _items.where((delivery) => '${delivery['status']}' == 'delivered' && !_settled(delivery) && _matches(delivery)).toList();
  }

  List<Map<String, dynamic>> get _paid {
    return _items.where((delivery) => _settled(delivery) && _matches(delivery)).toList();
  }

  bool _matches(Map<String, dynamic> delivery) {
    return rowMatches(delivery, _query, const ['customer_name', 'customer_phone', 'address', 'public_ref', 'zone_name']);
  }

  String _driverName(Map<String, dynamic> delivery) {
    final driver = delivery['driver'];
    if (driver is Map && '${driver['name'] ?? ''}'.trim().isNotEmpty) return '${driver['name']}';
    final name = '${delivery['driver_name'] ?? ''}'.trim();
    return name.isEmpty ? 'Non assigné' : name;
  }

  String _driverKey(Map<String, dynamic> delivery) {
    final driver = delivery['driver'];
    final id = driver is Map ? driver['id'] : delivery['driver_id'];
    if (id != null && '$id'.isNotEmpty) return 'id:$id';
    return 'name:${_driverName(delivery)}';
  }

  Map<String, List<Map<String, dynamic>>> _byDriver(List<Map<String, dynamic>> rows) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final delivery in rows) {
      grouped.putIfAbsent(_driverKey(delivery), () => []).add(delivery);
    }
    return grouped;
  }

  Future<void> _openDriver(String name, List<Map<String, dynamic>> orders) async {
    final unpaid = orders.where((item) => !_settled(item)).toList();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 460,
          child: unpaid.isEmpty
              ? const Text('Aucune commande à encaisser.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final delivery in unpaid)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${delivery['customer_name'] ?? 'Commande'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text('${delivery['address'] ?? ''} · ${delivery['customer_phone'] ?? ''}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(posMoney(_amount(delivery)), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            if (_manage) const Text('Marquer payé', style: TextStyle(color: PosColors.accent, fontWeight: FontWeight.w800)),
                          ],
                        ),
                        onTap: _manage
                            ? () {
                                Navigator.pop(context);
                                _markPaid(delivery);
                              }
                            : null,
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        ],
      ),
    );
  }

  Widget _driverBoard() {
    final grouped = _byDriver(_items.where((delivery) => '${delivery['status']}' == 'delivered').toList());
    if (grouped.isEmpty) return const SizedBox.shrink();
    final keys = grouped.keys.toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 720 ? 3 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final key in keys)
              SizedBox(
                width: width,
                child: _driverCard(_driverName(grouped[key]!.first), grouped[key]!),
              ),
          ],
        );
      },
    );
  }

  Widget _driverCard(String name, List<Map<String, dynamic>> orders) {
    final unpaid = orders.where((item) => !_settled(item)).toList();
    final amount = unpaid.fold<num>(0, (sum, item) => sum + _amount(item));
    final count = unpaid.length;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: count == 0 ? PosColors.line : PosColors.accent.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openDriver(name, orders),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(posMoney(amount), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: PosColors.accent)),
              const SizedBox(height: 4),
              Text(count == 1 ? '1 commande' : '$count commandes', style: const TextStyle(color: PosColors.muted, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
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
    final labels = ['À assigner', 'Paiements', if (_manage) 'Zones'];
    final index = _tab >= labels.length ? 0 : _tab;
    return Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!, style: const TextStyle(color: PosColors.danger)),
        if (_fromCache)
          const Text('Données enregistrées sur la tablette.', style: TextStyle(color: PosColors.accent, fontWeight: FontWeight.w700)),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (var i = 0; i < labels.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: ChoiceChip(
                    label: Text(labels[i]),
                    selected: index == i,
                    onSelected: (_) => setState(() => _tab = i),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: [ _assignTab(), _payTab(), if (_manage) _zonesTab() ][index]),
      ],
    );
  }

  Widget _searchBar() {
    return ListTile(
      leading: const Icon(Icons.search),
      title: Text(_query.isEmpty ? 'Code commande, client, téléphone…' : _query),
      onTap: () async {
        final field = TextEditingController(text: _query);
        final value = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Recherche'),
            content: TextField(controller: field, decoration: const InputDecoration(hintText: 'Code commande, client, téléphone…')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Effacer')),
              FilledButton(onPressed: () => Navigator.pop(context, field.text), child: const Text('Chercher')),
            ],
          ),
        );
        if (value == null || !mounted) return;
        setState(() => _query = value.trim());
      },
    );
  }

  Widget _assignTab() {
    final rows = _toAssign;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _searchBar(),
        if (rows.isEmpty) const Text('Aucune commande à assigner.', style: TextStyle(color: PosColors.muted)),
        for (final delivery in rows) _card(delivery, assign: true),
        if (_onRoute.isNotEmpty) const Padding(padding: EdgeInsets.only(top: 12), child: Text('En cours', style: TextStyle(fontWeight: FontWeight.w800))),
        for (final delivery in _onRoute) _card(delivery, advance: true),
      ],
    );
  }

  Widget _payTab() {
    final rows = _showPaid ? _paid : _due;
    final due = _items.where((item) => '${item['status']}' == 'delivered' && !_settled(item)).fold<num>(0, (sum, item) => sum + _amount(item));
    final paid = _items.where(_settled).fold<num>(0, (sum, item) => sum + _amount(item));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _searchBar(),
        Text('Dû ${posMoney(due)} · Payé ${posMoney(paid)} · Reste ${posMoney(due)}', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        if (!_showPaid) _driverBoard(),
        if (!_showPaid && _due.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('Rien à régler.', style: TextStyle(color: PosColors.muted))),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: () => setState(() => _showPaid = !_showPaid), child: Text(_showPaid ? 'File de travail' : 'Payées')),
        ),
        if (rows.isEmpty && _showPaid) const Text('Aucune commande payée.', style: TextStyle(color: PosColors.muted)),
        if (_showPaid)
          for (final delivery in rows) _card(delivery),
      ],
    );
  }

  Widget _zonesTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_manage)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => _editZone(), icon: const Icon(Icons.add), label: const Text('Zone')),
          ),
        if (_zones.isEmpty)
          const Text('Synchronisez les zones une fois en ligne.', style: TextStyle(color: PosColors.muted)),
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
      ],
    );
  }

  StatusTone _tone(String status) {
    return switch (status) {
      'pending' => StatusTone.waiting,
      'assigned' => StatusTone.assigned,
      'picked_up' || 'out_for_delivery' => StatusTone.progress,
      'delivered' => StatusTone.delivered,
      'cancelled' => StatusTone.cancelled,
      _ => StatusTone.neutral,
    };
  }

  Widget _card(Map<String, dynamic> delivery, {bool assign = false, bool pay = false, bool advance = false}) {
    final status = '${delivery['status']}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: MatchText(text: '${delivery['customer_name'] ?? ''}', query: _query)),
                StatusChip(label: _settled(delivery) ? 'Payée' : (_statusLabels[status] ?? status), tone: _settled(delivery) ? StatusTone.paid : _tone(status)),
              ],
            ),
            Text('${delivery['address'] ?? ''}'),
            Text('${delivery['customer_phone'] ?? ''}'),
            Wrap(
              spacing: 6,
              children: [
                if ('${delivery['customer_phone'] ?? ''}'.isNotEmpty)
                  TextButton(onPressed: () => _call('${delivery['customer_phone']}'), child: const Text('Appeler')),
                if (assign && _manage) TextButton(onPressed: () => _assign(delivery), child: const Text('Assigner')),
                if (advance && _manage && _nextStatus(status) != null)
                  TextButton(onPressed: () => _status(delivery, _nextStatus(status)!), child: Text(_statusLabels[_nextStatus(status)] ?? 'Avancer')),
                if (pay && _manage) TextButton(onPressed: () => _markPaid(delivery), child: const Text('Marquer payé')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
