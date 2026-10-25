import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../main.dart';
import '../printing/printer_service.dart';
import 'session_dialog.dart';

/// Mouvement de caisse : dépense (charges du magasin), entrée ou sortie d'argent. En ligne uniquement.
/// Retourne true si un mouvement a été enregistré.
Future<bool> showCashMovement(BuildContext context, {String kind = 'expense'}) async {
  final app = AppState.instance;
  if (!await app.checkOnline()) {
    if (context.mounted) await showOnlineRequired(context, 'Connectez-vous à Internet pour enregistrer un mouvement de caisse : les espèces disponibles sont vérifiées sur le serveur.');
    return false;
  }
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _MovementDialog(kind: kind));
  return ok == true;
}

class _MovementDialog extends StatefulWidget {
  const _MovementDialog({required this.kind});

  final String kind;

  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  static const _suggestions = {
    'expense': ['Transport', 'Repas', 'Fournitures', 'Ménage', 'Électricité', 'Eau', 'Loyer', 'Internet / téléphone', 'Réparation'],
    'in': ['Monnaie', 'Apport', 'Remboursement'],
    'out': ['Dépôt à la banque', 'Remise au gérant', 'Avance salaire'],
  };
  late String _kind = widget.kind;
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _busy = false;
  bool _print = true;
  String? _error;

  Future<void> _save() async {
    final app = AppState.instance;
    final amount = toNum(_amount.text.trim());
    final reason = _reason.text.trim();
    if (amount <= 0) {
      setState(() => _error = 'Saisissez un montant supérieur à 0.');
      return;
    }
    if (reason.isEmpty) {
      setState(() => _error = 'Le motif est obligatoire.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final report = await app.cashMovement(_kind, amount.toStringAsFixed(2), reason);
      final label = app.movements[_kind] ?? _kind;
      final printer = PrinterService.instance.config;
      if (printer != null && printer.ready && _print) {
        final now = DateTime.now();
        String two(int v) => v.toString().padLeft(2, '0');
        try {
          await PrinterService.instance.printMovement(
            label: label,
            amount: amount.toStringAsFixed(2),
            reason: reason,
            date: '${two(now.day)}/${two(now.month)}/${now.year} ${two(now.hour)}:${two(now.minute)}',
            openDrawer: true,
          );
        } catch (e) {
          if (mounted) toast(context, 'Impression : $e', error: true);
        }
      }
      if (!mounted) return;
      toast(context, '$label de ${amount.toStringAsFixed(2)} ${app.currency} enregistrée · espèces en caisse : ${report['expected_cash']} ${app.currency}');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final cur = app.currency;
    final expected = app.session?['expected_cash'];
    return AlertDialog(
      title: const Text('Mouvement de caisse'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', icon: Icon(Icons.receipt_outlined), label: Text('Dépense')),
                ButtonSegment(value: 'in', icon: Icon(Icons.south_west), label: Text('Entrée')),
                ButtonSegment(value: 'out', icon: Icon(Icons.north_east), label: Text('Sortie')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() {
                _kind = s.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 6),
            Text(
              _kind == 'expense'
                  ? 'Charge du magasin payée avec l’argent de la caisse.'
                  : _kind == 'in'
                      ? 'Argent ajouté dans la caisse (monnaie, apport).'
                      : 'Argent retiré de la caisse (banque, gérant).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (expected != null) Text('Espèces en caisse : $expected $cur', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Montant ($cur) *', prefixIcon: const Icon(Icons.payments_outlined)),
            ),
            const SizedBox(height: 10),
            TextField(controller: _reason, maxLength: 255, decoration: const InputDecoration(labelText: 'Motif *')),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final s in _suggestions[_kind] ?? const <String>[]) ActionChip(label: Text(s), onPressed: () => setState(() => _reason.text = s)),
            ]),
            if (PrinterService.instance.config?.ready == true)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _print,
                onChanged: (v) => setState(() => _print = v ?? true),
                title: const Text('Imprimer le bon (avec signature)'),
              ),
            if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Annuler')),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
          label: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
