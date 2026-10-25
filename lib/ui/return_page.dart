import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../main.dart';
import '../printing/printer_service.dart';
import 'scanner_page.dart';
import 'session_dialog.dart';

/// Retour total ou partiel d'un ticket (en ligne) : scan ou saisie du numéro, quantités, état, motif, remboursement.
class ReturnPage extends StatefulWidget {
  const ReturnPage({super.key, this.number});

  final String? number;

  @override
  State<ReturnPage> createState() => _ReturnPageState();
}

class _ReturnPageState extends State<ReturnPage> {
  static const _reasons = ['Taille', 'Défaut', 'Changement d’avis', 'Erreur de caisse'];
  final app = AppState.instance;
  final _number = TextEditingController();
  final _reason = TextEditingController();
  final _focus = FocusNode();
  Map<String, dynamic>? _sale;
  final Map<int, int> _qty = {};
  final Map<int, String> _condition = {};
  String _refund = 'cash';
  bool _busy = false;
  String? _error;
  String? _uuid;

  @override
  void initState() {
    super.initState();
    if ((widget.number ?? '').isNotEmpty) {
      _number.text = widget.number!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _lines => (_sale?['lines'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  double get _estimate {
    double sum = 0;
    for (final l in _lines) {
      final q = _qty[l['id']] ?? 0;
      final qty = (l['quantity'] as num).toInt();
      if (q > 0 && qty > 0) sum += double.parse(l['net_total'].toString()) * q / qty;
    }
    return sum;
  }

  Future<void> _lookup() async {
    final number = _number.text.trim();
    if (number.isEmpty) return;
    if (!await app.checkOnline()) {
      if (mounted) await showOnlineRequired(context, 'Connectez-vous à Internet pour faire un retour : le ticket et le stock sont vérifiés sur le serveur.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sale = await app.returnLookup(number);
      setState(() {
        _sale = sale;
        _qty.clear();
        _condition.clear();
        _uuid = app.newUuid();
        _refund = 'cash';
      });
    } catch (e) {
      setState(() {
        _sale = null;
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      _focus.requestFocus();
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScannerPage()));
    if (code == null) return;
    _number.text = code;
    await _lookup();
  }

  void _all() {
    setState(() {
      for (final l in _lines) {
        _qty[l['id'] as int] = (l['returnable'] as num).toInt();
      }
    });
  }

  Future<void> _submit() async {
    final lines = [
      for (final l in _lines)
        if ((_qty[l['id']] ?? 0) > 0) {'sale_line_id': l['id'], 'quantity': _qty[l['id']], 'condition': _condition[l['id']] ?? 'good'},
    ];
    if (lines.isEmpty) {
      setState(() => _error = 'Indiquez au moins un article à retourner.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Le motif du retour est obligatoire.');
      return;
    }
    if (!await app.checkOnline()) {
      if (mounted) await showOnlineRequired(context, 'Connectez-vous à Internet pour enregistrer le retour.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final doc = await app.createReturn({
        'request_uuid': _uuid ?? app.newUuid(),
        'sale_id': _sale!['id'],
        'refund_method': _refund,
        'reason': _reason.text.trim(),
        'lines': lines,
      });
      String? printError;
      final printer = PrinterService.instance.config;
      if (printer != null && printer.ready) {
        try {
          await PrinterService.instance.printReturn(doc, openDrawer: doc['refund_method'] == 'cash' && double.parse(doc['refund'].toString()) > 0);
        } catch (e) {
          printError = e.toString();
        }
      }
      if (!mounted) return;
      await _done(doc, printError);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _done(Map<String, dynamic> doc, String? printError) async {
    final cur = app.currency;
    final voucher = doc['voucher'];
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.assignment_return, color: Colors.green, size: 44),
        title: Text('Retour ${doc['number']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${doc['total']} $cur', style: Theme.of(c).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          if (double.parse(doc['debt'].toString()) > 0) Text('Déduit du dû client : ${doc['debt']} $cur'),
          if (double.parse(doc['refund'].toString()) > 0) Text('${doc['refund_label']} : ${doc['refund']} $cur', style: Theme.of(c).textTheme.titleMedium),
          if (voucher is Map) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Bon d’avoir ${voucher['code']}', style: const TextStyle(fontWeight: FontWeight.bold))),
          if (printError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Impression : $printError', style: const TextStyle(color: Colors.red))),
        ]),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.print_outlined),
            label: const Text('Imprimer'),
            onPressed: () async {
              try {
                await PrinterService.instance.printReturn(doc);
              } catch (e) {
                if (context.mounted) toast(context, e.toString(), error: true);
              }
            },
          ),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Terminer')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cur = app.currency;
    final sale = _sale;
    return Scaffold(
      appBar: AppBar(title: const Text('Retour d’articles')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _number,
              focusNode: _focus,
              autofocus: (widget.number ?? '').isEmpty,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(labelText: 'Numéro du ticket', hintText: 'Scanner ou saisir, ex. T-2026-000123', prefixIcon: Icon(Icons.receipt_long_outlined)),
              onSubmitted: (_) => _lookup(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(tooltip: 'Scanner avec la caméra', onPressed: _busy ? null : _scan, icon: const Icon(Icons.photo_camera_outlined)),
          const SizedBox(width: 8),
          FilledButton(onPressed: _busy ? null : _lookup, child: const Text('Chercher')),
        ]),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (sale != null) ...[
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              title: Text('Ticket ${sale['number']} · ${sale['total']} $cur'),
              subtitle: Text([
                sale['date'],
                if (sale['contact'] is Map) (sale['contact'] as Map)['name'],
                if (double.parse(sale['returned_total'].toString()) > 0) 'déjà retourné ${sale['returned_total']} $cur',
              ].join(' · ')),
              trailing: TextButton(onPressed: _all, child: const Text('Tout retourner')),
            ),
          ),
          const SizedBox(height: 8),
          for (final l in _lines) _lineTile(l),
          const SizedBox(height: 12),
          TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Motif du retour *')),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [for (final r in _reasons) ActionChip(label: Text(r), onPressed: () => setState(() => _reason.text = r))]),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: [for (final e in app.refunds.entries) ButtonSegment(value: e.key, label: Text(e.value), icon: Icon(e.key == 'cash' ? Icons.payments_outlined : Icons.card_giftcard))],
            selected: {_refund},
            onSelectionChanged: (s) => setState(() => _refund = s.first),
          ),
          if (double.parse((sale['debt_left'] ?? '0').toString()) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Ce client doit encore ${sale['debt_left']} $cur : le retour réduit d’abord son dû.', style: const TextStyle(fontSize: 12)),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
            onPressed: _busy ? null : _submit,
            icon: const Icon(Icons.assignment_return),
            label: Text('Valider le retour · environ ${_estimate.toStringAsFixed(2)} $cur'),
          ),
        ],
      ]),
    );
  }

  Widget _lineTile(Map<String, dynamic> l) {
    final id = l['id'] as int;
    final max = (l['returnable'] as num).toInt();
    final q = _qty[id] ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l['label'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('Vendu ${l['quantity']} · déjà retourné ${l['returned']} · ${l['net_total']} ${app.currency}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
              if (q > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [ButtonSegment(value: 'good', label: Text('Bon état')), ButtonSegment(value: 'damaged', label: Text('Endommagé'))],
                    selected: {_condition[id] ?? 'good'},
                    onSelectionChanged: (s) => setState(() => _condition[id] = s.first),
                  ),
                ),
            ]),
          ),
          if (max == 0)
            const Text('Déjà retourné', style: TextStyle(color: Colors.black45))
          else ...[
            IconButton(onPressed: q > 0 ? () => setState(() => _qty[id] = q - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
            Text('$q / $max', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            IconButton(onPressed: q < max ? () => setState(() => _qty[id] = q + 1) : null, icon: const Icon(Icons.add_circle_outline)),
          ],
        ]),
      ),
    );
  }
}
