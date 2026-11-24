import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../providers/app_providers.dart';
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
  final _counted = TextEditingController();
  final _movementAmount = TextEditingController();
  final _movementReason = TextEditingController();
  String _movementType = 'cash_in';
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _load() async {
    final online = ref.read(onlineProvider).valueOrNull ?? true;
    if (!online) {
      setState(() => _error = 'Tiroir : connexion requise.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get('/api/v1/cash/session');
      final raw = response.data['data'];
      setState(() {
        _session = raw is Map ? Map<String, dynamic>.from(raw) : null;
      });
      await ref.read(syncServiceProvider).refreshCashStatus();
    } on DioException catch (e) {
      setState(() {
        _session = null;
        _error = e.response?.data?['message']?.toString() ?? 'Impossible de lire le tiroir.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    final online = ref.read(onlineProvider).valueOrNull ?? true;
    if (!online) {
      setState(() => _error = 'Ouverture caisse impossible hors-ligne.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).post('/api/v1/cash/sessions', data: {
        'opening_amount': double.tryParse(_opening.text.replaceAll(',', '.')) ?? 0,
      });
      await _load();
    } on DioException catch (e) {
      setState(() => _error = e.response?.data?.toString() ?? 'Ouverture refusée.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _move() async {
    final id = _session?['id'] ?? _session?['session']?['id'];
    if (id == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).post(
        '/api/v1/cash/sessions/$id/movements',
        data: {
          'type': _movementType,
          'amount': double.tryParse(_movementAmount.text.replaceAll(',', '.')) ?? 0,
          'reason': _movementReason.text.trim(),
        },
      );
      _movementAmount.clear();
      _movementReason.clear();
      await _load();
    } on DioException catch (e) {
      setState(() => _error = e.response?.data?.toString() ?? 'Mouvement refusé.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    final id = _session?['id'] ?? _session?['session']?['id'];
    if (id == null) return;
    final online = ref.read(onlineProvider).valueOrNull ?? true;
    if (!online) {
      setState(() => _error = 'Fermeture caisse impossible hors-ligne.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).post(
        '/api/v1/cash/sessions/$id/close',
        data: {
          'closing_counted': double.tryParse(_counted.text.replaceAll(',', '.')) ?? 0,
        },
      );
      await _load();
    } on DioException catch (e) {
      setState(() => _error = e.response?.data?.toString() ?? 'Fermeture refusée.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _session ?? {};
    final status = '${data['status'] ?? 'closed'}';
    final isOpen = _session != null && (status == 'open' || data['id'] != null);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          isOpen ? 'Session ouverte' : 'Aucune fermée',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'L’ouverture et la fermeture nécessitent le réseau.',
          style: TextStyle(color: PosColors.muted),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: PosColors.danger)),
        ],
        const SizedBox(height: 16),
        if (!isOpen) ...[
          _padField(_opening, 'Fond de caisse', () => _editAmount(_opening, 'Fond de caisse')),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _busy ? null : _open,
            child: const Text('Ouvrir le tiroir'),
          ),
        ] else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Session: ${data['id'] ?? data['session']?['id'] ?? '—'}'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ChoiceChip(
                label: const Text('Entrée'),
                selected: _movementType == 'cash_in',
                onSelected: (_) => setState(() => _movementType = 'cash_in'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Sortie'),
                selected: _movementType == 'cash_out',
                onSelected: (_) => setState(() => _movementType = 'cash_out'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Dépense'),
                selected: _movementType == 'expense',
                onSelected: (_) => setState(() => _movementType = 'expense'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _padField(_movementAmount, 'Montant', () => _editAmount(_movementAmount, 'Montant')),
          const SizedBox(height: 8),
          _padField(_movementReason, 'Motif', () => _editText(_movementReason, 'Motif')),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _busy ? null : _move, child: const Text('Enregistrer mouvement')),
          const Divider(height: 32),
          _padField(_counted, 'Espèces comptées', () => _editAmount(_counted, 'Espèces comptées')),
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: PosColors.danger),
            onPressed: _busy ? null : _close,
            child: const Text('Fermer le tiroir'),
          ),
        ],
        const SizedBox(height: 12),
        TextButton(onPressed: _busy ? null : _load, child: const Text('Actualiser')),
      ],
    );
  }
}
