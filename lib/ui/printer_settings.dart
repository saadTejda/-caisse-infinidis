import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../printing/printer_presets.dart';
import '../printing/printer_service.dart';

/// Réglage de l'imprimante ticket : appareil (modèle reconnu tout seul), marque / modèle, papier,
/// réglages avancés, ticket test et assistant de correction.
Future<void> showPrinterSettings(BuildContext context) =>
    showDialog(context: context, barrierDismissible: false, builder: (_) => const _PrinterDialog());

class _PrinterDialog extends StatefulWidget {
  const _PrinterDialog();

  @override
  State<_PrinterDialog> createState() => _PrinterDialogState();
}

class _PrinterDialogState extends State<_PrinterDialog> {
  late PrinterConfig _c;
  late String _brand;
  final _host = TextEditingController();
  final _port = TextEditingController();
  List<BluetoothInfo> _devices = [];
  bool _loading = false;
  bool _testing = false;
  bool _wizard = false;
  String? _message;
  bool _error = false;

  static const _pages = [16, 2, 19, 0];
  static const _cuts = ['feed', 'full', 'partial'];

  @override
  void initState() {
    super.initState();
    final saved = PrinterService.instance.config;
    _c = saved != null ? PrinterConfig.fromJson(saved.toJson()) : PrinterConfig.fromPreset(presetById('generic_58'));
    _brand = presetById(_c.presetId).brand;
    _host.text = _c.host;
    _port.text = '${_c.port}';
    if (_c.connection == 'bluetooth') _loadDevices();
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final list = await PrinterService.instance.pairedDevices();
      if (!mounted) return;
      setState(() => _devices = list);
      if (list.isEmpty) {
        _say('Aucun appareil appairé : allumez l’imprimante, appairez-la dans les réglages Bluetooth d’Android (code souvent 0000 ou 1234), puis actualisez.', error: true);
      } else if (_c.address.isEmpty) {
        final guess = list.where((d) => detectPreset(d.name) != null).toList();
        if (guess.length == 1) _pick(guess.first);
      }
    } catch (e) {
      _say(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pick(BluetoothInfo d) {
    final found = detectPreset(d.name);
    setState(() {
      _c.address = d.macAdress;
      _c.deviceName = d.name;
      _wizard = false;
      if (found != null) {
        _c.applyPreset(found);
        _brand = found.brand;
      }
    });
    if (found != null) {
      _say('Modèle reconnu : ${found.label} (${found.paper} mm). Réglages appliqués : faites le ticket test.');
    } else {
      _say('Modèle non reconnu d’après le nom « ${d.name} » : choisissez la marque et le modèle, ou gardez « Autre imprimante 58 / 80 mm », puis faites le ticket test.');
    }
  }

  void _say(String m, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = m;
      _error = error;
    });
  }

  void _collect() {
    _c.host = _host.text.trim();
    _c.port = int.tryParse(_port.text.trim()) ?? 9100;
  }

  Future<void> _test({String? note}) async {
    _collect();
    if (!_c.ready) {
      _say(_c.connection == 'network' ? 'Saisissez l’adresse IP de l’imprimante.' : 'Choisissez d’abord l’imprimante Bluetooth.', error: true);
      return;
    }
    setState(() => _testing = true);
    try {
      await PrinterService.instance.printTest(_c);
      if (mounted) setState(() => _wizard = true);
      _say('${note != null ? '$note\n' : ''}Ticket test imprimé : regardez-le et répondez ci-dessous.');
    } catch (e) {
      _say(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _fixAccents() {
    String note;
    if (!_c.accents) {
      _c.accents = true;
      _c.codePage = _pages.first;
      note = 'Nouvel essai des accents : ${codePages[_c.codePage]}.';
    } else {
      final i = _pages.indexOf(_c.codePage);
      if (i + 1 < _pages.length) {
        _c.codePage = _pages[i + 1];
        note = 'Nouvel essai des accents : ${codePages[_c.codePage]}.';
      } else {
        _c.accents = false;
        note = 'Accents retirés (é → e) : le ticket reste lisible sur toutes les imprimantes.';
      }
    }
    setState(() {});
    _test(note: note);
  }

  void _fixCut() {
    String note;
    if (!_c.cut) {
      _c.cut = true;
      _c.cutMode = _cuts.first;
      note = 'Coupe activée : ${cutModes[_c.cutMode]}.';
    } else {
      final i = _cuts.indexOf(_c.cutMode);
      if (i + 1 < _cuts.length) {
        _c.cutMode = _cuts[i + 1];
        note = 'Nouvel essai de coupe : ${cutModes[_c.cutMode]}.';
      } else {
        _c.cut = false;
        _c.cutMode = 'none';
        note = 'Cette imprimante ne coupe pas : coupe désactivée (déchirez le ticket).';
      }
    }
    setState(() {});
    _test(note: note);
  }

  void _fixWidth({required bool tooWide}) {
    const steps = [32, 42, 48];
    final i = steps.indexOf(_c.columns);
    if (tooWide) {
      if (_c.paper >= 80 && i > 0) {
        _c.columns = steps[i - 1];
      } else {
        _c.paper = 58;
        _c.columns = 32;
      }
    } else {
      if (_c.paper < 80) {
        _c.paper = 80;
        _c.columns = 42;
      } else {
        _c.columns = i >= 0 && i + 1 < steps.length ? steps[i + 1] : 48;
      }
    }
    setState(() {});
    _test(note: 'Largeur réglée : ${_c.paper} mm, ${_c.columns} caractères par ligne.');
  }

  void _fixBarcode() {
    _c.barcode = false;
    setState(() {});
    _test(note: 'Code-barres remplacé par le numéro en gros caractères.');
  }

  Future<void> _testDrawer({bool switchPin = false}) async {
    _collect();
    if (!_c.ready) {
      _say('Choisissez d’abord l’imprimante.', error: true);
      return;
    }
    setState(() {
      if (switchPin) _c.drawerPin = _c.drawerPin == 1 ? 0 : 1;
      _c.drawer = true;
      _testing = true;
    });
    try {
      await PrinterService.instance.testDrawer(_c);
      _say('Ouverture du tiroir envoyée (broche ${_c.drawerPin == 1 ? 5 : 2}). Le tiroir doit être branché sur l’imprimante (prise RJ11).');
    } catch (e) {
      _say(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    _collect();
    if (!_c.ready) {
      _say(_c.connection == 'network' ? 'Saisissez l’adresse IP de l’imprimante.' : 'Choisissez l’imprimante Bluetooth.', error: true);
      return;
    }
    await PrinterService.instance.save(_c);
    if (mounted) Navigator.pop(context);
  }

  Widget _wizardPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget fix(String label, IconData icon, VoidCallback onTap) =>
        OutlinedButton.icon(onPressed: _testing ? null : onTap, icon: Icon(icon, size: 18), label: Text(label));
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.primaryContainer.withOpacity(0.35), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Le ticket test est-il correct ?', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text('Chaque bouton corrige le réglage et réimprime le test.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: _testing ? null : _save, icon: const Icon(Icons.check), label: const Text('Tout est bon : enregistrer')),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          fix('Accents en symboles bizarres', Icons.translate, _fixAccents),
          fix('Ligne pleine coupée en 2', Icons.compress, () => _fixWidth(tooWide: true)),
          fix('Ligne pleine trop courte', Icons.expand, () => _fixWidth(tooWide: false)),
          fix('Code-barres absent ou illisible', Icons.qr_code_2, _fixBarcode),
          fix(_c.cut ? 'Papier non coupé' : 'Je veux la coupe auto', Icons.content_cut, _fixCut),
          fix('Tester le tiroir', Icons.point_of_sale, _testDrawer),
          if (_c.drawer) fix('Le tiroir ne s’ouvre pas', Icons.sync_alt, () => _testDrawer(switchPin: true)),
          fix('Rien ne s’imprime / illisible', Icons.help_outline, () {
            _say(
              'Vérifiez que l’imprimante est allumée, chargée, avec du papier (face thermique vers l’extérieur) et appairée. '
              'Ticket complètement illisible : choisissez « Autre imprimante 58 / 80 mm ». Imprimante Star : réglez-la en émulation ESC/POS.',
              error: true,
            );
          }),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preset = presetById(_c.presetId);
    final models = printerPresets.where((p) => p.brand == _brand).toList();
    final small = Theme.of(context).textTheme.bodySmall;
    return AlertDialog(
      title: const Text('Imprimante ticket'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'bluetooth', icon: Icon(Icons.bluetooth), label: Text('Bluetooth')),
                ButtonSegment(value: 'network', icon: Icon(Icons.lan_outlined), label: Text('Réseau / Wi-Fi')),
              ],
              selected: {_c.connection},
              onSelectionChanged: (s) {
                setState(() {
                  _c.connection = s.first;
                  _wizard = false;
                });
                if (_c.connection == 'bluetooth' && _devices.isEmpty) _loadDevices();
              },
            ),
            const SizedBox(height: 12),
            if (_c.connection == 'bluetooth')
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _devices.any((d) => d.macAdress == _c.address) ? _c.address : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: _c.address.isNotEmpty && !_devices.any((d) => d.macAdress == _c.address) ? 'Imprimante (${_c.deviceName})' : 'Imprimante appairée',
                    ),
                    items: [
                      for (final d in _devices)
                        DropdownMenuItem(
                          value: d.macAdress,
                          child: Text(
                            '${d.name}${detectPreset(d.name) != null ? '  ✓ ${detectPreset(d.name)!.label}' : ''}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (mac) {
                      final d = _devices.where((x) => x.macAdress == mac);
                      if (d.isNotEmpty) _pick(d.first);
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Actualiser',
                  onPressed: _loading ? null : _loadDevices,
                  icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
                ),
              ])
            else
              Row(children: [
                Expanded(flex: 3, child: TextField(controller: _host, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Adresse IP', hintText: '192.168.1.100'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port'))),
              ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: _brand,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Marque'),
                  items: [for (final b in printerBrands) DropdownMenuItem(value: b, child: Text(b == 'Autre' ? 'Autre / inconnue' : b))],
                  onChanged: (b) {
                    if (b == null) return;
                    setState(() {
                      _brand = b;
                      _c.applyPreset(printerPresets.firstWhere((p) => p.brand == b));
                      _wizard = false;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_brand),
                  value: models.any((p) => p.id == _c.presetId) ? _c.presetId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Modèle'),
                  items: [for (final p in models) DropdownMenuItem(value: p.id, child: Text('${p.model} · ${p.paper} mm', overflow: TextOverflow.ellipsis))],
                  onChanged: (id) {
                    if (id == null) return;
                    setState(() {
                      _c.applyPreset(presetById(id));
                      _wizard = false;
                    });
                  },
                ),
              ),
            ]),
            if (preset.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(preset.note, style: small)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('paper-${_c.paper}'),
                  value: _c.paper,
                  decoration: const InputDecoration(labelText: 'Papier'),
                  items: const [DropdownMenuItem(value: 58, child: Text('58 mm')), DropdownMenuItem(value: 80, child: Text('80 mm'))],
                  onChanged: (v) => setState(() {
                    _c.paper = v ?? 58;
                    _c.columns = _c.paper == 80 ? 48 : 32;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('cols-${_c.columns}'),
                  value: [32, 42, 48].contains(_c.columns) ? _c.columns : 32,
                  decoration: const InputDecoration(labelText: 'Caractères / ligne'),
                  items: const [DropdownMenuItem(value: 32, child: Text('32')), DropdownMenuItem(value: 42, child: Text('42')), DropdownMenuItem(value: 48, child: Text('48'))],
                  onChanged: (v) => setState(() => _c.columns = v ?? 32),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _c.copies,
                  decoration: const InputDecoration(labelText: 'Copies'),
                  items: const [DropdownMenuItem(value: 1, child: Text('1')), DropdownMenuItem(value: 2, child: Text('2')), DropdownMenuItem(value: 3, child: Text('3'))],
                  onChanged: (v) => setState(() => _c.copies = v ?? 1),
                ),
              ),
            ]),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _c.autoPrint, onChanged: (v) => setState(() => _c.autoPrint = v), title: const Text('Imprimer le ticket après chaque vente')),
            if (_c.connection == 'bluetooth')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _c.keepAlive,
                onChanged: (v) => setState(() => _c.keepAlive = v),
                title: const Text('Garder la connexion Bluetooth'),
                subtitle: const Text('Connexion au démarrage et reconnexion automatique : le ticket sort tout de suite.'),
              ),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _c.drawer, onChanged: (v) => setState(() => _c.drawer = v), title: const Text('Ouvrir le tiroir-caisse (paiement espèces)')),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text('Réglages avancés'),
              subtitle: Text('Coupe, accents, code-barres, tiroir', style: small),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _c.cut,
                  onChanged: (v) => setState(() {
                    _c.cut = v;
                    _c.cutMode = v ? (_c.cutMode == 'none' ? 'feed' : _c.cutMode) : 'none';
                  }),
                  title: const Text('Coupe automatique du papier'),
                ),
                if (_c.cut)
                  DropdownButtonFormField<String>(
                    key: ValueKey('cut-${_c.cutMode}'),
                    value: _cuts.contains(_c.cutMode) ? _c.cutMode : 'feed',
                    decoration: const InputDecoration(labelText: 'Commande de coupe'),
                    items: [for (final m in _cuts) DropdownMenuItem(value: m, child: Text(cutModes[m]!))],
                    onChanged: (v) => setState(() => _c.cutMode = v ?? 'feed'),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _c.accents,
                  onChanged: (v) => setState(() => _c.accents = v),
                  title: const Text('Imprimer les accents (é, à, ç)'),
                  subtitle: const Text('Désactivé : accents retirés (é → e).'),
                ),
                if (_c.accents)
                  DropdownButtonFormField<int>(
                    key: ValueKey('page-${_c.codePage}'),
                    value: _pages.contains(_c.codePage) ? _c.codePage : 16,
                    decoration: const InputDecoration(labelText: 'Page de caractères'),
                    items: [for (final p in _pages) DropdownMenuItem(value: p, child: Text(codePages[p]!))],
                    onChanged: (v) => setState(() => _c.codePage = v ?? 16),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _c.barcode,
                  onChanged: (v) => setState(() => _c.barcode = v),
                  title: const Text('Imprimer le code-barres du ticket'),
                  subtitle: const Text('Désactivé : numéro en gros caractères.'),
                ),
                if (_c.drawer)
                  DropdownButtonFormField<int>(
                    key: ValueKey('pin-${_c.drawerPin}'),
                    value: _c.drawerPin,
                    decoration: const InputDecoration(labelText: 'Branchement du tiroir'),
                    items: const [DropdownMenuItem(value: 0, child: Text('Broche 2 (la plus courante)')), DropdownMenuItem(value: 1, child: Text('Broche 5'))],
                    onChanged: (v) => setState(() => _c.drawerPin = v ?? 0),
                  ),
              ],
            ),
            if (_message != null)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(color: _error ? Colors.red.shade50 : Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text(_message!, style: TextStyle(color: _error ? Colors.red.shade800 : Colors.green.shade800)),
              ),
            if (_wizard) _wizardPanel(context),
          ]),
        ),
      ),
      actions: [
        if (PrinterService.instance.config != null)
          TextButton(
            onPressed: () async {
              await PrinterService.instance.remove();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Sans imprimante'),
          ),
        OutlinedButton.icon(
          onPressed: _testing ? null : () => _test(),
          icon: _testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.print_outlined),
          label: const Text('Ticket test'),
        ),
        TextButton(
          onPressed: () {
            PrinterService.instance.check();
            Navigator.pop(context);
          },
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }
}
