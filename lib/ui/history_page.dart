import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../main.dart';
import '../printing/printer_service.dart';
import 'movement_dialog.dart';
import 'return_page.dart';
import 'session_dialog.dart';

/// Ventes de la caisse depuis son ouverture : résumé, ventes hors ligne en attente, puis ventes enregistrées.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final app = AppState.instance;
  Map<String, dynamic>? _report;
  List<Map<String, dynamic>> _sales = [];
  List<Map<String, dynamic>> _pending = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _pending = await app.db.outbox(statuses: ['pending', 'error']);
    try {
      if (!await app.checkOnline()) throw Exception('Hors ligne : seules les ventes gardées sur la tablette sont affichées.');
      final data = await app.sessionSales();
      _report = Map<String, dynamic>.from(data['report'] as Map);
      _sales = (data['sales'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _n(dynamic v) => double.tryParse((v ?? '0').toString()) ?? 0;

  Future<void> _open(Map<String, dynamic> row) async {
    Map<String, dynamic> sale;
    try {
      sale = await app.saleDetail(row['id'] as int);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
      return;
    }
    if (!mounted) return;
    final cur = app.currency;
    final canReturn = app.abilities['return'] == true && row['fully_returned'] != true;
    final action = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Ticket ${sale['number']}'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${sale['date']} · ${sale['cashier']}${sale['contact'] is Map ? ' · ${(sale['contact'] as Map)['name']}' : ''}'),
              const Divider(),
              for (final raw in (sale['lines'] as List? ?? []))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [Expanded(child: Text('${raw['quantity']} × ${raw['label']}')), Text('${raw['total']}')]),
                ),
              const Divider(),
              if (_n(sale['shipping']) > 0) Text('Expédition : ${sale['shipping']} $cur'),
              Text('Total : ${sale['total']} $cur', style: const TextStyle(fontWeight: FontWeight.bold)),
              for (final p in (sale['payments'] as List? ?? [])) Text('${p['method']} : ${p['amount']}'),
              if (_n(sale['due']) > 0) Text('Reste dû (crédit) : ${sale['due']} $cur'),
              if (sale['shipment'] is Map) Text('À livrer · colis ${(sale['shipment'] as Map)['code']} · à encaisser ${sale['cod']} $cur'),
              if (_n(sale['returned_total']) > 0) Text('Retourné : ${sale['returned_total']} $cur', style: const TextStyle(color: Colors.deepOrange)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer')),
          if (canReturn) OutlinedButton.icon(onPressed: () => Navigator.pop(c, 'return'), icon: const Icon(Icons.assignment_return_outlined), label: const Text('Retour')),
          FilledButton.icon(onPressed: () => Navigator.pop(c, 'print'), icon: const Icon(Icons.print_outlined), label: const Text('Réimprimer')),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'print') {
      try {
        await PrinterService.instance.printTicket(app.ticketFromSale(sale));
      } catch (e) {
        if (mounted) toast(context, e.toString(), error: true);
      }
    }
    if (action == 'return') {
      final done = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ReturnPage(number: sale['number'].toString())));
      if (done == true) await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = app.currency;
    final r = _report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique de la caisse'),
        actions: [
          if (app.abilities['expense'] == true)
            TextButton.icon(
              onPressed: () async {
                if (await showCashMovement(context)) await _load();
              },
              icon: const Icon(Icons.swap_vert),
              label: const Text('Mouvement'),
            ),
          IconButton(tooltip: 'Actualiser', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          if (_loading) const LinearProgressIndicator(),
          if (r != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 24, runSpacing: 8, children: [
                  _stat('Ouverte le', '${r['opened_at']}\npar ${r['opened_by']}'),
                  _stat('Fond de caisse', '${r['opening_float']} $cur'),
                  _stat('Ventes', '${r['sales_count']} · ${r['sales_total']} $cur'),
                  if (_n(r['returns_count']) > 0) _stat('Retours', '${r['returns_count']} · ${r['returns_total']} $cur'),
                  if (_n(r['cod']) > 0) _stat('À encaisser (livraisons)', '${r['deliveries']} · ${r['cod']} $cur'),
                  if (_n(r['credit']) > 0) _stat('Crédit accordé', '${r['credit']} $cur'),
                  if (_n(r['expenses']) > 0) _stat('Dépenses', '-${r['expenses']} $cur'),
                  if (_n(r['cash_in']) > 0) _stat('Entrées d’argent', '+${r['cash_in']} $cur'),
                  if (_n(r['cash_out']) > 0) _stat('Sorties d’argent', '-${r['cash_out']} $cur'),
                  _stat('Espèces attendues', '${r['expected_cash']} $cur', strong: true),
                ]),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                const Icon(Icons.wifi_off, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!)),
                TextButton(
                  onPressed: () => showOnlineRequired(context, 'Connectez-vous à Internet pour voir les ventes de la caisse.').then((_) => _load()),
                  child: const Text('Réessayer'),
                ),
              ]),
            ),
          if (r != null && (r['movements'] as List? ?? []).isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Text('Mouvements de caisse (${(r['movements'] as List).length})', style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final m in (r['movements'] as List))
              Card(
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    m['kind'].toString().startsWith('Entrée') ? Icons.south_west : (m['kind'].toString().startsWith('Dépense') ? Icons.receipt_outlined : Icons.north_east),
                    color: m['kind'].toString().startsWith('Entrée') ? Colors.green : Colors.deepOrange,
                  ),
                  title: Text('${m['kind']} · ${m['amount']} $cur'),
                  subtitle: Text('${m['at']} · ${m['reason']}'),
                ),
              ),
          ],
          if (_pending.isNotEmpty) ...[
            Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 4), child: Text('Hors ligne, pas encore envoyées (${_pending.length})', style: Theme.of(context).textTheme.titleSmall)),
            for (final p in _pending) _pendingTile(p),
          ],
          if (_sales.isNotEmpty)
            Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 4), child: Text('Ventes de la caisse (${_sales.length})', style: Theme.of(context).textTheme.titleSmall)),
          for (final s in _sales) _saleTile(s, cur),
          if (!_loading && _sales.isEmpty && _pending.isEmpty && _error == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Aucune vente depuis l’ouverture de la caisse.'))),
        ]),
      ),
    );
  }

  Widget _saleTile(Map<String, dynamic> s, String cur) {
    final returned = s['fully_returned'] == true && _n(s['returned']) > 0;
    final deliver = s['to_deliver'] == true;
    return Card(
      child: ListTile(
        onTap: () => _open(s),
        leading: CircleAvatar(
          backgroundColor: returned ? Colors.grey.shade300 : (deliver ? Colors.blue.shade50 : Colors.green.shade50),
          child: Icon(deliver ? Icons.local_shipping_outlined : Icons.receipt_long_outlined, size: 20),
        ),
        title: Text('${s['number']} · ${s['total']} $cur'),
        subtitle: Text([
          '${s['at']}',
          if ((s['contact'] ?? '').toString().isNotEmpty) '${s['contact']}',
          if ((s['methods'] ?? '').toString().isNotEmpty) '${s['methods']}',
          if (s['offline'] == true) 'faite hors ligne',
          if (_n(s['due']) > 0) 'crédit ${s['due']}',
          if (deliver) 'à livrer ${s['cod']}',
          if (_n(s['returned']) > 0) (returned ? 'retournée' : 'retour ${s['returned']}'),
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  Widget _pendingTile(Map<String, dynamic> row) {
    final ticket = Map<String, dynamic>.from(jsonDecode(row['ticket'].toString()) as Map);
    final error = row['status'] == 'error';
    return Card(
      child: ListTile(
        leading: Icon(error ? Icons.error_outline : Icons.schedule, color: error ? Colors.red : Colors.orange),
        title: Text('${row['local_number']} · ${ticket['total']} ${app.currency}'),
        subtitle: Text(error ? 'Refusée : ${row['message']}' : '${ticket['date']} · en attente d’envoi'),
        trailing: IconButton(
          tooltip: 'Réimprimer',
          icon: const Icon(Icons.print_outlined),
          onPressed: () async {
            try {
              await PrinterService.instance.printTicket(ticket);
            } catch (e) {
              if (mounted) toast(context, e.toString(), error: true);
            }
          },
        ),
      ),
    );
  }

  Widget _stat(String label, String value, {bool strong = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          Text(value, style: TextStyle(fontWeight: strong ? FontWeight.bold : FontWeight.w500, fontSize: strong ? 18 : 14)),
        ],
      );
}
