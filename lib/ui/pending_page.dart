import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../main.dart';
import '../printing/printer_service.dart';

/// Ventes faites hors ligne : en attente d'envoi, refusées (à vérifier) et envoyées récemment.
class PendingPage extends StatefulWidget {
  const PendingPage({super.key});

  @override
  State<PendingPage> createState() => _PendingPageState();
}

class _PendingPageState extends State<PendingPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await AppState.instance.db.outbox(statuses: ['error', 'pending', 'sent']);
    rows.sort((a, b) => b['created_at'].toString().compareTo(a['created_at'].toString()));
    if (mounted) setState(() => _rows = rows.take(200).toList());
  }

  Future<void> _send() async {
    final app = AppState.instance;
    setState(() => _sending = true);
    if (!await app.checkOnline()) {
      if (mounted) toast(context, 'Toujours hors ligne : les ventes partiront au retour de la connexion.', error: true);
    } else {
      final n = await app.pushOutbox();
      if (mounted) toast(context, n > 0 ? '$n vente(s) envoyée(s).' : 'Aucune vente envoyée.');
    }
    await _load();
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Supprimer ${row['local_number']} ?'),
        content: const Text('La vente refusée sera retirée de la tablette. Le stock et la caisse du serveur ne la contiennent pas : refaites-la si la marchandise est partie.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    await AppState.instance.db.deleteOutbox(row['uuid'].toString());
    await AppState.instance.pushOutbox();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cur = AppState.instance.currency;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ventes hors ligne'),
        actions: [
          TextButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload_outlined),
            label: const Text('Envoyer'),
          ),
        ],
      ),
      body: _rows.isEmpty
          ? const Center(child: Text('Aucune vente hors ligne.'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final r = _rows[i];
                  final ticket = Map<String, dynamic>.from(jsonDecode(r['ticket'].toString()) as Map);
                  final status = r['status'].toString();
                  final (IconData icon, Color color, String label) = switch (status) {
                    'sent' => (Icons.cloud_done_outlined, Colors.green, 'Envoyée · ${r['number']}'),
                    'error' => (Icons.error_outline, Colors.red, 'Refusée : ${r['message']}'),
                    _ => (Icons.schedule, Colors.orange, r['message'] != null ? 'En attente · ${r['message']}' : 'En attente d’envoi'),
                  };
                  return ListTile(
                    leading: Icon(icon, color: color),
                    title: Text('${r['local_number']} · ${ticket['total']} $cur · ${ticket['date']}'),
                    subtitle: Text(label, style: TextStyle(color: status == 'error' ? Colors.red.shade700 : null)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Réimprimer',
                        icon: const Icon(Icons.print_outlined),
                        onPressed: () async {
                          try {
                            await PrinterService.instance.printTicket(ticket);
                          } catch (e) {
                            if (context.mounted) toast(context, e.toString(), error: true);
                          }
                        },
                      ),
                      if (status == 'error') ...[
                        IconButton(
                          tooltip: 'Renvoyer',
                          icon: const Icon(Icons.replay),
                          onPressed: () async {
                            await AppState.instance.db.retry(r['uuid'].toString());
                            await _send();
                          },
                        ),
                        IconButton(tooltip: 'Supprimer', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(r)),
                      ],
                    ]),
                  );
                },
              ),
            ),
    );
  }
}
