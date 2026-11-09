import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../main.dart';
import '../printing/label_printer.dart';
import 'developer_footer.dart';
import 'setup_page.dart';

/// Poste d'impression et réglages de cet appareil.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final app = AppState.instance;
  late final _name = TextEditingController(text: app.settings.stationName);
  late final _host = TextEditingController(text: app.settings.host);
  late final _port = TextEditingController(text: '${app.settings.port}');
  bool _testing = false;

  void _set(VoidCallback change) {
    change();
    setState(() {});
  }

  Future<void> _pickBluetooth() async {
    try {
      final devices = await LabelPrinter.pairedDevices();
      if (!mounted) return;
      if (devices.isEmpty) {
        toast(context, 'Aucune imprimante appairée : appairez-la d’abord dans les réglages Bluetooth d’Android.', error: true);
        return;
      }
      final picked = await showModalBottomSheet<int>(
        context: context,
        builder: (c) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Imprimantes appairées', style: TextStyle(fontWeight: FontWeight.bold))),
              for (var i = 0; i < devices.length; i++)
                ListTile(leading: const Icon(Icons.print), title: Text(devices[i].name), subtitle: Text(devices[i].macAdress), onTap: () => Navigator.pop(c, i)),
            ],
          ),
        ),
      );
      if (picked != null) {
        _set(() {
          app.settings.btAddress = devices[picked].macAdress;
          app.settings.btName = devices[picked].name;
        });
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _test() async {
    final ids = [...app.done.map((d) => asInt(d['id'])), ...app.queue.map((q) => asInt(q['id']))];
    final id = app.order != null ? asInt(app.order!['id']) : (ids.isNotEmpty ? ids.first : 0);
    if (id == 0) {
      toast(context, 'Il faut au moins une commande dans la file ou préparée aujourd’hui pour le test.', error: true);
      return;
    }
    setState(() => _testing = true);
    try {
      await LabelPrinter.printLabels([id]);
      if (mounted) toast(context, 'Étiquette test envoyée.');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = app.settings;
    final title = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold);
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages · poste d’impression')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nom du poste', hintText: 'Ex. Tablette préparation 1', prefixIcon: Icon(Icons.badge_outlined)),
            onChanged: (v) => s.stationName = v,
          ),
          const SizedBox(height: 20),
          Text('Étiquette', style: title),
          RadioListTile<int>(value: 0, groupValue: s.labelFormat, onChanged: (v) => _set(() => s.labelFormat = v!), title: const Text('Adaptée au livreur'), subtitle: const Text('10 × 15 ou 10 × 10 selon la fiche du livreur, avec son logo')),
          RadioListTile<int>(value: 6, groupValue: s.labelFormat, onChanged: (v) => _set(() => s.labelFormat = v!), title: const Text('10 × 15 cm')),
          RadioListTile<int>(value: 5, groupValue: s.labelFormat, onChanged: (v) => _set(() => s.labelFormat = v!), title: const Text('10 × 10 cm')),
          ListTile(
            title: const Text('Copies'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(onPressed: s.copies > 1 ? () => _set(() => s.copies = s.copies - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
              Text('${s.copies}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(onPressed: s.copies < 5 ? () => _set(() => s.copies = s.copies + 1) : null, icon: const Icon(Icons.add_circle_outline)),
            ]),
          ),
          const SizedBox(height: 12),
          Text('Imprimante', style: title),
          RadioListTile<String>(value: 'android', groupValue: s.printMode, onChanged: (v) => _set(() => s.printMode = v!), title: const Text('Impression Android'),
              subtitle: const Text('Toute imprimante installée sur la tablette (Wi-Fi, service d’impression du fabricant). Vous choisissez l’imprimante à chaque fois.')),
          RadioListTile<String>(value: 'network', groupValue: s.printMode, onChanged: (v) => _set(() => s.printMode = v!), title: const Text('Imprimante d’étiquettes réseau (sans clic)'),
              subtitle: const Text('Imprimante thermique en TSPL (Xprinter, TSC, Gprinter…) branchée au réseau, port 9100.')),
          if (s.printMode == 'network')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Expanded(flex: 3, child: TextField(controller: _host, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Adresse IP', hintText: '192.168.1.50'), onChanged: (v) => s.host = v)),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port'), onChanged: (v) => s.port = int.tryParse(v) ?? 9100)),
              ]),
            ),
          RadioListTile<String>(value: 'bluetooth', groupValue: s.printMode, onChanged: (v) => _set(() => s.printMode = v!), title: const Text('Imprimante d’étiquettes Bluetooth (sans clic)'),
              subtitle: const Text('Imprimante thermique en TSPL appairée à la tablette.')),
          if (s.printMode == 'bluetooth')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: OutlinedButton.icon(onPressed: _pickBluetooth, icon: const Icon(Icons.bluetooth_searching), label: Text(s.btName.isNotEmpty ? '${s.btName} · ${s.btAddress}' : 'Choisir l’imprimante appairée')),
            ),
          if (s.printMode != 'android')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<int>(
                segments: const [ButtonSegment(value: 8, label: Text('203 dpi')), ButtonSegment(value: 12, label: Text('300 dpi'))],
                selected: {s.dotsPerMm},
                onSelectionChanged: (v) => _set(() => s.dotsPerMm = v.first),
              ),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.tonalIcon(onPressed: _testing ? null : _test, icon: const Icon(Icons.print_outlined), label: Text(_testing ? 'Envoi…' : 'Imprimer une étiquette test')),
          ),
          const SizedBox(height: 20),
          Text('Fonctionnement', style: title),
          SwitchListTile(value: s.autoPrint, onChanged: (v) => _set(() => s.autoPrint = v), title: const Text('Imprimer l’étiquette à « Préparé »')),
          SwitchListTile(value: s.autoFinish, onChanged: (v) => _set(() => s.autoFinish = v), title: const Text('Valider « Préparé » tout seul quand tout est scanné')),
          SwitchListTile(value: s.sound, onChanged: (v) => _set(() => s.sound = v), title: const Text('Sons de validation et d’erreur')),
          SwitchListTile(value: s.keepAwake, onChanged: (v) => _set(() {
                s.keepAwake = v;
                app.applyWake();
              }), title: const Text('Garder l’écran allumé')),
          const SizedBox(height: 20),
          Text('Compte', style: title),
          ListTile(leading: const Icon(Icons.person_outline), title: Text((app.user?['name'] ?? '').toString()), subtitle: Text((app.user?['role_label'] ?? '').toString())),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: Text(app.serverName),
            subtitle: Text(app.serverUrl),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SetupPage(changing: true))),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await app.logout();
              },
              icon: const Icon(Icons.logout),
              label: const Text('Se déconnecter'),
            ),
          ),
          const DeveloperFooter(),
        ],
      ),
    );
  }
}
