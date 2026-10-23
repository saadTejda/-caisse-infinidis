import 'package:flutter/material.dart';

import '../core/app_state.dart';

/// Adresse du serveur INFINIDIS Gestion (modifiable : une même application pour plusieurs commerçants).
class SetupPage extends StatefulWidget {
  const SetupPage({super.key, this.changing = false});

  final bool changing;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _url = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url.text = AppState.instance.serverUrl.isNotEmpty ? AppState.instance.serverUrl : 'https://gestionlivraison.saadtejda.com';
  }

  Future<void> _save() async {
    final app = AppState.instance;
    final changingServer = app.serverUrl.isNotEmpty && app.serverUrl != _url.text.trim();
    if (changingServer && (app.pending > 0 || app.errors > 0)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Ventes non envoyées'),
          content: Text('${app.pending + app.errors} vente(s) de cette caisse ne sont pas encore sur le serveur actuel. Changer de serveur les supprimera de la tablette.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Changer quand même')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.setServer(_url.text);
      if (mounted && widget.changing) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.changing ? AppBar(title: const Text('Serveur')) : null,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.point_of_sale, size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text('Caisse INFINIDIS', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text('Saisissez l’adresse de votre application de gestion.', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Adresse du serveur', hintText: 'https://votre-site.com', prefixIcon: Icon(Icons.link)),
                  onSubmitted: (_) => _save(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                  label: const Text('Vérifier et enregistrer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
