import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import 'contact_picker.dart';
import 'delivery_dialog.dart';
import 'session_dialog.dart';

class PaymentResult {
  PaymentResult(this.payload, this.contact, {required this.cash, required this.totals});

  /// Champs ajoutés à la vente : payments, cash_received, credit, et pour une livraison deliver, delivery, shipping.
  final Map<String, dynamic> payload;
  final Contact? contact;
  final bool cash;

  /// Totaux affichés (frais d'expédition compris).
  final Totals totals;
}

/// [totalsFor] recalcule les totaux du panier avec les frais d'expédition donnés.
Future<PaymentResult?> showPayment(BuildContext context, {required Totals Function(double shipping) totalsFor, Contact? contact}) =>
    showDialog<PaymentResult>(context: context, barrierDismissible: false, builder: (_) => _PaymentDialog(totalsFor: totalsFor, contact: contact));

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.totalsFor, this.contact});

  final Totals Function(double shipping) totalsFor;
  final Contact? contact;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  static const _others = ['card', 'transfer', 'cheque'];
  final _cash = TextEditingController();
  final _amounts = {for (final m in _others) m: TextEditingController()};
  final _refs = {for (final m in _others) m: TextEditingController()};
  Contact? _contact;
  bool _credit = false;
  DeliveryInfo? _delivery;

  Totals get _totals => widget.totalsFor(_delivery?.shipping ?? 0);
  double get _total => _totals.total;

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
    _cash.text = _total.toStringAsFixed(2);
  }

  double _v(TextEditingController c) {
    final v = toNum(c.text.trim());
    return v > 0 ? v : 0;
  }

  double get _nonCash => _others.fold<double>(0, (s, m) => s + _v(_amounts[m]!));
  double get _cashApplied => (_total - _nonCash).clamp(0, _v(_cash)).toDouble();
  double get _change => (_v(_cash) - _cashApplied).clamp(0, double.infinity).toDouble();
  double get _due => Totals.round2(_total - _nonCash - _cashApplied);

  Future<void> _toggleCredit(bool on) async {
    final app = AppState.instance;
    if (on && !await app.checkOnline()) {
      if (mounted) await showOnlineRequired(context, 'Connectez-vous à Internet pour vérifier le crédit du client. La vente à crédit n’est pas possible hors ligne.');
      if (!app.online) return;
    }
    if (on && _contact == null && mounted) {
      final c = await pickContact(context);
      if (c == null) return;
      _contact = c;
    }
    setState(() {
      _credit = on;
      if (on) _delivery = null;
    });
  }

  Future<void> _toggleDelivery(bool on) async {
    if (!on) {
      setState(() => _delivery = null);
      return;
    }
    final app = AppState.instance;
    if (!await app.checkOnline()) {
      if (mounted) await showOnlineRequired(context, 'Connectez-vous à Internet pour créer une livraison : le colis doit être enregistré sur le serveur.');
      if (!app.online) return;
    }
    if (!mounted) return;
    final info = await showDeliveryForm(context, initial: _delivery, contact: _contact);
    if (info == null) return;
    final wasExact = (_v(_cash) - _total).abs() < 0.001;
    setState(() {
      _delivery = info;
      _credit = false;
      if (wasExact) _cash.text = _total.toStringAsFixed(2);
    });
  }

  Future<void> _validate() async {
    final app = AppState.instance;
    if (_nonCash > _total + 0.001) {
      _alert('Les paiements carte, virement et chèque dépassent le total.');
      return;
    }
    if (_due > 0.001 && !_credit && _delivery == null) {
      _alert('Il manque ${_due.toStringAsFixed(2)} ${app.currency} : complétez le paiement${app.abilities['credit'] == true ? ', vendez à crédit' : ''} ou cochez « À livrer ».');
      return;
    }
    if ((_credit && _due > 0.001) || _delivery != null) {
      if (!await app.checkOnline()) {
        if (mounted) {
          await showOnlineRequired(context, _delivery != null ? 'Connectez-vous à Internet pour créer la livraison.' : 'Connectez-vous à Internet pour vérifier le crédit du client.');
        }
        return;
      }
      if (_credit && _contact == null) {
        _alert('Choisissez le client pour une vente à crédit.');
        return;
      }
    }
    final payments = [
      for (final m in _others)
        if (_v(_amounts[m]!) > 0) {'method': m, 'amount': _v(_amounts[m]!).toStringAsFixed(2), 'reference': _refs[m]!.text.trim()},
    ];
    if (!mounted) return;
    Navigator.pop(
      context,
      PaymentResult(
        {
          'payments': payments,
          'cash_received': _v(_cash).toStringAsFixed(2),
          'credit': _credit && _due > 0.001,
          if (_delivery != null) ...{
            'deliver': true,
            'delivery': _delivery!.toPayload(),
            'shipping': _delivery!.shipping.toStringAsFixed(2),
          },
        },
        _contact,
        cash: _cashApplied > 0,
        totals: _totals,
      ),
    );
  }

  void _alert(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red.shade700));
  }

  Widget _quick(String label, double value) => ActionChip(label: Text(label), onPressed: () => setState(() => _cash.text = value.toStringAsFixed(2)));

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final cur = app.currency;
    final t = _total;
    final rounds = <double>{for (final step in [10, 50, 100, 200]) ((t / step).ceil() * step).toDouble()}.where((v) => v > t).take(3);
    final d = _delivery;
    return AlertDialog(
      title: Row(children: [
        const Expanded(child: Text('Encaisser')),
        Text('${t.toStringAsFixed(2)} $cur', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      ]),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _cash,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Espèces reçues ($cur)', prefixIcon: const Icon(Icons.payments_outlined)),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              _quick('Exact', t),
              for (final v in rounds) _quick(v.toStringAsFixed(0), v),
              ActionChip(label: const Text('0'), onPressed: () => setState(() => _cash.text = '0')),
            ]),
            const SizedBox(height: 12),
            for (final m in _others)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _amounts[m],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: app.methods[m] ?? m,
                        suffixIcon: IconButton(
                          tooltip: 'Le reste',
                          icon: const Icon(Icons.south_west, size: 18),
                          onPressed: () => setState(() {
                            final others = _others.where((o) => o != m).fold<double>(0, (s, o) => s + _v(_amounts[o]!));
                            _amounts[m]!.text = (t - others).clamp(0, t).toStringAsFixed(2);
                            _cash.text = '0';
                          }),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (m != 'card') ...[
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: TextField(controller: _refs[m], decoration: const InputDecoration(labelText: 'Référence'))),
                  ],
                ]),
              ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: d != null,
              onChanged: _toggleDelivery,
              secondary: const Icon(Icons.local_shipping_outlined),
              title: const Text('À livrer'),
              subtitle: Text(d == null
                  ? (app.online ? 'Le reste sera encaissé à la livraison' : 'Hors ligne : livraison impossible')
                  : '${d.fullName} · ${d.cityName}${d.shipping > 0 ? ' · expédition ${d.shipping.toStringAsFixed(2)} $cur' : ''}'),
            ),
            if (d != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(onPressed: () => _toggleDelivery(true), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Modifier la livraison')),
              ),
            _line('Rendu monnaie', '${_change.toStringAsFixed(2)} $cur', bold: _change > 0),
            _line(d != null ? 'À encaisser à la livraison' : 'Reste à payer', '${(_due > 0 ? _due : 0).toStringAsFixed(2)} $cur',
                color: _due > 0.001 && d == null ? Colors.red : null, bold: _due > 0.001),
            if (app.abilities['credit'] == true && d == null) ...[
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _credit,
                onChanged: _toggleCredit,
                title: const Text('Vente à crédit (reste dû au client)'),
                subtitle: Text(!app.online
                    ? 'Hors ligne : crédit impossible'
                    : _contact == null
                        ? 'Choisissez un client'
                        : '${_contact!.name}${_contact!.available != null ? ' · crédit disponible ${_contact!.available!.toStringAsFixed(2)} $cur (dernière synchro)' : ''}'),
              ),
            ],
            if (_contact != null && !_credit) Text('Client : ${_contact!.name}', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton.icon(onPressed: _validate, icon: const Icon(Icons.check), label: const Text('Valider la vente')),
      ],
    );
  }

  Widget _line(String label, String value, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color, fontSize: 16)),
        ]),
      );
}
