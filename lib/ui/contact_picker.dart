import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';

/// Choix du client parmi les contacts synchronisés (fonctionne hors ligne).
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

  @override
  Widget build(BuildContext context) {
    final currency = AppState.instance.currency;
    return AlertDialog(
      title: const Text('Client'),
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
                  ? const Center(child: Text('Aucun contact. Synchronisez les contacts si un client vient d’être créé.', textAlign: TextAlign.center))
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
