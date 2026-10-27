import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../printing/printer_service.dart';

/// Ouverture de caisse (fond de caisse). Nécessite Internet.
Future<bool> showOpenSession(BuildContext context) async {
  final app = AppState.instance;
  if (!await app.checkOnline()) {
    if (context.mounted) await showOnlineRequired(context, 'Connectez-vous à Internet pour ouvrir la caisse.');
    return false;
  }
  if (!context.mounted) return false;
  final amount = TextEditingController(text: '0');
  String? error;
  bool busy = false;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text('Ouvrir la caisse'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Magasin : ${app.store?['name'] ?? '—'}'),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Fond de caisse (${app.currency})'),
            ),
            if (error != null) ...[const SizedBox(height: 8), Text(error!, style: const TextStyle(color: Colors.red))],
          ]),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await app.openSession(amount.text.replaceAll(',', '.'));
                      PrinterService.instance.check();
                      if (c.mounted) Navigator.pop(c, true);
                    } catch (e) {
                      setState(() {
                        error = e.toString();
                        busy = false;
                      });
                    }
                  },
            child: const Text('Ouvrir'),
          ),
        ],
      ),
    ),
  );
  return ok == true;
}

/// Clôture : envoie d'abord les ventes en attente, puis comptage des espèces.
Future<void> showCloseSession(BuildContext context) async {
  final app = AppState.instance;
  if (!await app.checkOnline()) {
    if (context.mounted) await showOnlineRequired(context, 'Connectez-vous à Internet pour clôturer la caisse : les ventes hors ligne doivent d’abord être envoyées.');
    return;
  }
  await app.pushOutbox();
  if (!context.mounted) return;
  if (app.pending > 0 || app.errors > 0) {
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ventes à envoyer'),
        content: Text('${app.pending + app.errors} vente(s) ne sont pas encore acceptées par le serveur. Vérifiez « Ventes en attente » avant de clôturer.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
    return;
  }
  try {
    await app.syncContext();
  } catch (_) {}
  if (!context.mounted) return;
  final s = app.session;
  if (s == null) return;
  final counted = TextEditingController();
  final note = TextEditingController();
  String? error;
  bool busy = false;
  Map<String, dynamic>? report;
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        if (report != null) {
          final r = report!;
          return AlertDialog(
            title: Text('Caisse clôturée ${r['number'] ?? ''}'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ventes : ${r['sales_count']} · ${r['sales_total']} ${app.currency}'),
              Text('Espèces attendues : ${r['expected_cash']}'),
              Text('Espèces comptées : ${r['counted_cash'] ?? '—'}'),
              Text('Écart : ${r['difference'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
            actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Terminer'))],
          );
        }
        return AlertDialog(
          title: const Text('Clôturer la caisse'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Ouverte le ${s['opened_at'] ?? ''} par ${s['opened_by'] ?? ''}'),
              Text('${s['sales_count']} vente(s) · ${s['sales_total']} ${app.currency}'),
              Text('Espèces attendues : ${s['expected_cash']} ${app.currency}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: counted,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Espèces comptées (${app.currency})'),
              ),
              const SizedBox(height: 8),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (facultatif)')),
              if (error != null) ...[const SizedBox(height: 8), Text(error!, style: const TextStyle(color: Colors.red))],
            ]),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(c), child: const Text('Annuler')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final r = await app.closeSession(counted.text.replaceAll(',', '.'), note.text);
                        setState(() => report = r);
                      } catch (e) {
                        setState(() {
                          error = e.toString();
                          busy = false;
                        });
                      }
                    },
              child: const Text('Clôturer'),
            ),
          ],
        );
      },
    ),
  );
}

/// Popup « connexion nécessaire » (crédit, ouverture/clôture de caisse…).
Future<void> showOnlineRequired(BuildContext context, String message) async {
  final app = AppState.instance;
  var checking = false;
  await showDialog(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        return AlertDialog(
          icon: const Icon(Icons.wifi_off, size: 40, color: Colors.orange),
          title: const Text('Connexion Internet nécessaire'),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer')),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
              onPressed: checking
                  ? null
                  : () async {
                      setState(() => checking = true);
                      final ok = await app.checkOnline();
                      if (ok && c.mounted) Navigator.pop(c);
                      if (!ok && c.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Toujours hors ligne.')));
                        setState(() => checking = false);
                      }
                    },
            ),
          ],
        );
      },
    ),
  );
}
