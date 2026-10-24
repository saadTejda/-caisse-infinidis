import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import 'session_dialog.dart';

/// Choix du client parmi les contacts synchronisés (fonctionne hors ligne) ; création en ligne avec le droit « Contacts ».
Future<Contact?> pickContact(BuildContext context) => showDialog<Contact>(context: context, builder: (_) => const _ContactPicker());

class _ContactPicker extends StatefulWidget {
  const _ContactPicker();

  @override
  State<_ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends State<_ContactPicker> {
  final _q = TextEditingController();
  List<Contact> _items = [];

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    final items = await AppState.instance.db.contacts(query: _q.text);
    if (mounted) setState(() => _items = items);
  }

  Future<void> _create() async {
    final app = AppState.instance;
    if (!await app.checkOnline()) {
      if (mounted) await showOnlineRequired(context, 'Connectez-vous à Internet pour créer un client : il doit être enregistré sur le serveur.');
      return;
    }
    if (!mounted) return;
    final typed = _q.text.trim();
    final contact = await showDialog<Contact>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NewContactDialog(initial: typed),
    );
    if (contact != null && mounted) Navigator.pop(context, contact);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final currency = app.currency;
    final canCreate = app.abilities['contacts'] == true;
    return AlertDialog(
      title: Row(children: [
        const Expanded(child: Text('Client')),
        if (canCreate) FilledButton.tonalIcon(onPressed: _create, icon: const Icon(Icons.person_add_alt_1), label: const Text('Nouveau client')),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 480,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _q,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Nom ou téléphone', prefixIcon: Icon(Icons.search)),
              onChanged: (_) => _search(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _items.isEmpty
                  ? Center(
                      child: Text(
                        canCreate ? 'Aucun contact trouvé. Touchez « Nouveau client » pour le créer.' : 'Aucun contact. Synchronisez les contacts si un client vient d’être créé.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final c = _items[i];
                        return ListTile(
                          dense: true,
                          title: Text(c.name),
                          subtitle: Text([if (c.phone.isNotEmpty) c.phone, if (c.code.isNotEmpty) c.code].join(' · ')),
                          trailing: c.balance != 0 ? Text('Solde ${c.balance.toStringAsFixed(2)} $currency', style: const TextStyle(fontSize: 12)) : null,
                          onTap: () => Navigator.pop(context, c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler'))],
    );
  }
}

class _NewContactDialog extends StatefulWidget {
  const _NewContactDialog({required this.initial});

  final String initial;

  @override
  State<_NewContactDialog> createState() => _NewContactDialogState();
}

class _NewContactDialogState extends State<_NewContactDialog> {
  String _type = 'individual';
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _company = TextEditingController();
  final _phone = TextEditingController();
  final _ice = TextEditingController();
  final _city = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final v = widget.initial;
    if (RegExp(r'^\+?[\d\s.\-]{6,}$').hasMatch(v)) {
      _phone.text = v;
    } else {
      _first.text = v;
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final contact = await AppState.instance.createContact({
        'type': _type,
        if (_type == 'company') 'company_name': _company.text.trim() else ...{'first_name': _first.text.trim(), 'last_name': _last.text.trim()},
        'phone': _phone.text.trim(),
        'ice': _ice.text.trim(),
        'city': _city.text.trim(),
      });
      if (mounted) Navigator.pop(context, contact);
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
    return AlertDialog(
      title: const Text('Nouveau client'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'individual', icon: Icon(Icons.person_outline), label: Text('Particulier')),
                ButtonSegment(value: 'company', icon: Icon(Icons.business_outlined), label: Text('Entreprise')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            if (_type == 'company')
              TextField(controller: _company, autofocus: true, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nom de l’entreprise *'))
            else
              Row(children: [
                Expanded(child: TextField(controller: _first, autofocus: true, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Prénom *'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _last, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nom'))),
              ]),
            const SizedBox(height: 10),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone *', prefixIcon: Icon(Icons.phone_outlined))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: _city, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Ville'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _ice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ICE (15 chiffres)'))),
            ]),
            if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
          label: const Text('Créer'),
        ),
      ],
    );
  }
}
