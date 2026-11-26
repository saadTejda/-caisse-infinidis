import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../db/list_cache.dart';
import '../providers/app_providers.dart';
import '../services/order_queue.dart';
import '../theme/pos_theme.dart';
import 'pos_dialogs.dart';

class CashScreen extends ConsumerStatefulWidget {
  const CashScreen({super.key});

  @override
  ConsumerState<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends ConsumerState<CashScreen> {
  Map<String, dynamic>? _session;
  final _opening = TextEditingController(text: '0');
  final _openingNote = TextEditingController();
  List<Map<String, dynamic>> _history = [];
  final _counted = TextEditingController();
  final _closingNote = TextEditingController();
  final _movementAmount = TextEditingController();
  final _movementReason = TextEditingController();
  String _movementType = 'cash_in';
  String? _error;
  bool _busy = false;
  bool _fromCache = false;
  bool _sending = false;
  List<Map<String, dynamic>> _pending = [];
  late final OrderQueue _queue;

  @override
  void initState() {
    super.initState();
    _queue = ref.read(orderQueueProvider);
    _queue.flushing.addListener(_onFlush);
    _load();
  }

  @override
  void dispose() {
    _queue.flushing.removeListener(_onFlush);
    super.dispose();
  }

  void _onFlush() {
    if (!mounted) return;
    setState(() => _sending = _queue.flushing.value);
  }

  Future<void> _editAmount(TextEditingController controller, String title) async {
    final value = await showPosAmountPad(context, title: title, initial: controller.text);
    if (value == null || !mounted) return;
    setState(() => controller.text = value);
  }

  Future<void> _editText(TextEditingController controller, String title) async {
    final value = await showPosTextPad(context, title: title, initial: controller.text, hint: title);
    if (value == null || !mounted) return;
    setState(() => controller.text = value);
  }

  Widget _padField(TextEditingController controller, String label, VoidCallback onTap) {
    final empty = controller.text.trim().isEmpty;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: PosColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: PosColors.muted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                empty ? label : controller.text,
                style: TextStyle(color: empty ? PosColors.muted : PosColors.ink, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _readPending() async {
    try {
      final rows = await ref.read(orderQueueProvider).items();
      if (mounted) setState(() => _pending = rows);
    } catch (_) {}
  }

  double get _localCash {
    var sum = 0.0;
    for (final row in _pending) {
      final payload = row['payload'];
      if (payload is! Map) continue;
      if ('${payload['_op'] ?? 'sale'}' != 'sale') continue;
      if ('${payload['payment_method']}' != 'cash') continue;
      sum += double.tryParse('${payload['_local_total']}'.replaceAll(',', '.')) ?? 0;
    }
    return sum;
  }

  Future<void> _load() async {
    await _readPending();
    final online = ref.read(onlineProvider).valueOrNull ?? true;
    if (!online) {
      final cached = await loadList(ref.read(localStoreProvider), 'cash_session');
      setState(() {
        _session = cached.isEmpty ? null : cached.first;
        _fromCache = _session != null;
        _error = _session == null ? 'Pas encore synchronisé. Les totaux locaux restent visibles.' : null;
        _busy = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    Map<String, dynamic>? session;
    var history = <Map<String, dynamic>>[];
    String? error;
    final dio = ref.read(dioProvider);
    try {
      final response = await dio.get('/api/v1/cash/session');
      final raw = response.data is Map ? response.data['data'] : null;
      session = raw is Map ? Map<String, dynamic>.from(raw) : null;
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) error = apiMessage(e, fallback: 'Impossible de lire le tiroir.');
    }
    try {
      final response = await dio.get('/api/v1/cash/sessions');
      history = apiList(response.data);
    } on DioException catch (e) {
      error ??= apiMessage(e, fallback: 'Impossible de lire le tiroir.');
    }
    if (session != null) {
      await saveList(ref.read(localStoreProvider), 'cash_session', [session]);
    }
    if (mounted) {
      setState(() {
        _session = session;
        _history = history;
        _error = error;
        _fromCache = false;
      });
    }
    try {
      await ref.read(syncServiceProvider).refreshCashStatus();
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _open() async {
    final online = ref.read(onlineProvider).valueOrNull ?? true;
    if (!online) {
      setState(() => _error = 'Connectez-vous pour ouvrir la caisse. Le serveur ne répond pas.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).post('/api/v1/cash/sessions', data: {
        'opening_amount': double.tryParse(_opening.text.replaceAll(',', '.')) ?? 0,
        'opening_note': _openingNote.text.trim().isEmpty ? null : _openingNote.text.trim(),
      });
      await _load();
    } on DioException catch (e) {
      setState(() => _error = apiMessage(e, fallback: 'Ouverture refusée.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _move() async {
    final online = ref.read(onlineProvider).valueOrNull ?? false;
    if (!online) {
      setState(() => _error = 'Connectez-vous pour enregistrer un mouvement. Le serveur ne répond pas.');
      return;
    }
    final id = _session?['id'] ?? _session?['session']?['id'];
    if (id == null) return;
    final amount = double.tryParse(_movementAmount.text.replaceAll(',', '.')) ?? 0;
    if (amount <= 0 || _movementReason.text.trim().isEmpty) {
      setState(() => _error = 'Montant positif et motif obligatoires.');
      return;
    }
    setState(() => _busy = true);
    final label = _movementType == 'cash_out'
        ? 'Sortie de caisse'
        : _movementType == 'expense'
            ? 'Dépense'
            : 'Entrée de caisse';
    final reason = _movementReason.text.trim();
    try {
      await ref.read(dioProvider).post(
        '/api/v1/cash/sessions/$id/movements',
        data: {
          'type': _movementType,
          'amount': amount,
          'reason': reason,
        },
      );
      final settings = await ref.read(syncServiceProvider).settings();
      await ref.read(printServiceProvider).printMovement(
            settings: settings,
            label: label,
            amount: amount.toStringAsFixed(2),
            reason: reason,
          );
      _movementAmount.clear();
      _movementReason.clear();
      await _load();
    } on DioException catch (e) {
      setState(() => _error = apiMessage(e, fallback: 'Mouvement refusé.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    final id = _session?['id'] ?? _session?['session']?['id'];
    if (id == null) return;
    final online = ref.read(onlineProvider).valueOrNull ?? true;
    if (!online) {
      setState(() => _error = 'Connectez-vous pour fermer la caisse. Le serveur ne répond pas.');
      return;
    }
    await ref.read(orderQueueProvider).flush();
    final waiting = await ref.read(orderQueueProvider).pendingCount();
    if (waiting > 0) {
      setState(() => _error = 'Il reste des ventes à envoyer ou en erreur. Synchronisez avant de fermer la caisse.');
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await ref.read(dioProvider).post(
        '/api/v1/cash/sessions/$id/close',
        data: {
          'closing_counted': double.tryParse(_counted.text.replaceAll(',', '.')) ?? 0,
          'closing_note': _closingNote.text.trim().isEmpty ? null : _closingNote.text.trim(),
        },
      );
      final closed = apiMap(response.data);
      if (mounted && closed['variance'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Écart ${closed['variance']}')));
      }
      await _load();
    } on DioException catch (e) {
      setState(() => _error = apiMessage(e, fallback: 'Fermeture refusée.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _cash(dynamic value) {
    if (value == null || '$value'.isEmpty) return '—';
    final number = double.tryParse('$value'.replaceAll(',', '.'));
    if (number == null) return '$value';
    final parts = number.toStringAsFixed(2).split('.');
    return '${parts[0]},${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final data = _session ?? {};
    final status = '${data['status'] ?? 'closed'}';
    final isOpen = status == 'open';
    final totals = data['totals'] is Map ? Map<String, dynamic>.from(data['totals'] as Map) : const <String, dynamic>{};

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isOpen ? 'Session ouverte' : 'Aucune caisse ouverte',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Actualiser',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ],
        ),
        if (_sending)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Envoi en cours. Ne recliquez pas, reprise automatique.', style: TextStyle(color: PosColors.accent, fontWeight: FontWeight.w800)),
          ),
        if (_pending.any((row) => '${row['last_error'] ?? ''}'.contains('interrompu')))
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Envoi interrompu. Ne recliquez pas, reprise automatique.', style: TextStyle(color: PosColors.warning, fontWeight: FontWeight.w800)),
          ),
        if (_fromCache)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Totaux serveur enregistrés sur la tablette.', style: TextStyle(color: PosColors.muted, fontSize: 12)),
          ),
        if (isOpen) ...[
          Text(
            'Session ${data['id'] ?? '—'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: PosColors.muted, fontSize: 12),
          ),
          const Text(
            'La carte ne rentre pas dans le tiroir.',
            style: TextStyle(color: PosColors.muted, fontSize: 12),
          ),
        ]
        else
          const Text(
            'L’ouverture et la fermeture nécessitent le réseau.',
            style: TextStyle(color: PosColors.muted, fontSize: 12),
          ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: const TextStyle(color: PosColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 10),
        if (!isOpen) ...[
          Row(
            children: [
              Expanded(child: _padField(_opening, 'Fond de caisse', () => _editAmount(_opening, 'Fond de caisse'))),
              const SizedBox(width: 8),
              Expanded(child: _padField(_openingNote, 'Note', () => _editText(_openingNote, 'Note d’ouverture'))),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: _action('Ouvrir le tiroir', _open),
          ),
        ] else ...[
          _totalsGrid(data, totals),
          if (_localCash > 0 || _pending.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Totaux locaux (provisoires) · espèces ${_cash(((double.tryParse('${totals['expected'] ?? data['closing_expected']}'.replaceAll(',', '.')) ?? 0) + _localCash))} · ${_pending.length} en file',
              style: const TextStyle(fontWeight: FontWeight.w800, color: PosColors.accent),
            ),
          ],
          const SizedBox(height: 12),
          const Text('Mouvement', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            children: [
              _segment('Entrée', 'cash_in'),
              const SizedBox(width: 6),
              _segment('Sortie', 'cash_out'),
              const SizedBox(width: 6),
              _segment('Dépense', 'expense'),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 2, child: _padField(_movementAmount, 'Montant', () => _editAmount(_movementAmount, 'Montant'))),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: _padField(_movementReason, 'Motif', () => _editText(_movementReason, 'Motif'))),
              const SizedBox(width: 8),
              _action('Enregistrer', _move),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Fermeture', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(flex: 2, child: _padField(_counted, 'Espèces comptées', () => _editAmount(_counted, 'Espèces comptées'))),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: _padField(_closingNote, 'Note de fermeture', () => _editText(_closingNote, 'Note de fermeture'))),
              const SizedBox(width: 8),
              _action('Fermer', _close, danger: true, enabled: _pending.isEmpty && !_sending),
            ],
          ),
        ],
        const SizedBox(height: 16),
        const Text('Historique', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        const SizedBox(height: 4),
        for (final session in _history.take(12))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${session['opened_at'] ?? session['id']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${session['status']}', style: const TextStyle(fontSize: 12, color: PosColors.muted)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 88,
                  child: Text(
                    _cash(session['totals'] is Map ? (session['totals'] as Map)['expected'] : session['closing_expected']),
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _totalsGrid(Map<String, dynamic> data, Map<String, dynamic> totals) {
    final cells = <(String, String)>[
      ('Espèces attendues', _cash(totals['expected'] ?? data['closing_expected'])),
      ('Ventes espèces', _cash(totals['cash_sales'])),
      ('Entrées', _cash(totals['cash_in'])),
      ('Sorties', _cash(totals['cash_out'])),
      ('Dépenses', _cash(totals['expenses'])),
      if (data['variance'] != null) ('Écart', _cash(data['variance'])),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.4,
      children: [
        for (final cell in cells) _stat(cell.$1, cell.$2),
      ],
    );
  }

  Widget _stat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PosColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: PosColors.muted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _segment(String label, String value) {
    final selected = _movementType == value;
    return Expanded(
      child: Material(
        color: selected ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _movementType = value),
          child: Container(
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: selected ? const Color(0xFF111827) : PosColors.line),
            ),
            child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : PosColors.ink)),
          ),
        ),
      ),
    );
  }

  Widget _action(String label, VoidCallback onPressed, {bool danger = false, bool enabled = true}) {
    return FilledButton(
      onPressed: _busy || !enabled ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: danger ? PosColors.danger : const Color(0xFF111827),
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
    );
  }
}
