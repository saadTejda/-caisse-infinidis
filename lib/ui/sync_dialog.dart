import 'package:flutter/material.dart';

import '../core/app_state.dart';

/// Bouton « Synchroniser » : produits, contacts, ou tout (avec envoi des ventes en attente).
Future<void> showSyncDialog(BuildContext context) => showDialog(context: context, builder: (_) => const _SyncDialog());

class _SyncDialog extends StatefulWidget {
  const _SyncDialog();

  @override
  State<_SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<_SyncDialog> {
  String? _running;
  String? _result;
  bool _error = false;
  int _products = 0;
  int _images = 0;
  int _contacts = 0;

  @override
  void initState() {
    super.initState();
    _countLocal();
  }

  Future<void> _countLocal() async {
    final db = AppState.instance.db;
    final p = await db.productCount();
    final i = await db.productImageCount();
    final c = await db.contactCount();
    if (mounted) {
      setState(() {
        _products = p;
        _images = i;
        _contacts = c;
      });
    }
  }

  Future<void> _run(String what) async {
    final app = AppState.instance;
    setState(() {
      _running = what;
      _result = null;
      _error = false;
    });
    try {
      if (!await app.checkOnline()) throw Exception('Pas de connexion Internet : la synchronisation reprendra quand le réseau reviendra.');
      String message;
      switch (what) {
        case 'products':
          await app.syncContext();
          message = '${await app.syncCatalog()} produit(s) à jour.';
        case 'contacts':
          message = '${await app.syncContacts()} contact(s) à jour.';
        case 'sales':
          final sent = await app.pushOutbox();
          message = sent > 0 ? '$sent vente(s) envoyée(s).' : 'Aucune vente à envoyer.';
          if (app.errors > 0) message += ' ${app.errors} vente(s) refusée(s) à vérifier.';
        default:
          message = await app.syncAll();
      }
      setState(() => _result = message);
    } catch (e) {
      setState(() {
        _result = e.toString().replaceFirst('Exception: ', '');
        _error = true;
      });
    } finally {
      if (mounted) setState(() => _running = null);
      await _countLocal();
    }
  }

  Widget _action(String id, IconData icon, String title, String subtitle) {
    final busy = _running == id;
    return ListTile(
      leading: busy ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      enabled: _running == null,
      onTap: () => _run(id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final last = app.lastSync == null ? 'jamais' : _format(DateTime.tryParse(app.lastSync!));
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => AlertDialog(
        title: Row(children: [
          const Expanded(child: Text('Synchroniser')),
          Chip(
            avatar: Icon(app.online ? Icons.wifi : Icons.wifi_off, size: 16, color: app.online ? Colors.green : Colors.red),
            label: Text(app.online ? 'En ligne' : 'Hors ligne'),
          ),
        ]),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _action('all', Icons.sync, 'Tout synchroniser', 'Ventes en attente, caisse, produits et contacts'),
              _action('products', Icons.inventory_2_outlined, 'Produits', '$_products produit(s) sur la tablette · $_images avec image · prix et stock'),
              _action('contacts', Icons.people_outline, 'Contacts', '$_contacts contact(s) · nouveaux clients et soldes de crédit'),
              _action('sales', Icons.cloud_upload_outlined, 'Envoyer les ventes', '${app.pending} vente(s) en attente'),
              const SizedBox(height: 8),
              Text('Dernière synchronisation : $last', style: Theme.of(context).textTheme.bodySmall),
              if (_result != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: _error ? Colors.red.shade50 : Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Text(_result!, style: TextStyle(color: _error ? Colors.red.shade800 : Colors.green.shade800)),
                ),
              ],
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
      ),
    );
  }
}

String _format(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)} à ${two(l.hour)}:${two(l.minute)}';
}
