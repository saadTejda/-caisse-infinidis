import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../printing/printer_presets.dart';
import '../printing/printer_service.dart';

/// Réglage de l'imprimante ticket : modèle, connexion, papier, coupe, tiroir, test.
Future<void> showPrinterSettings(BuildContext context) => showDialog(context: context, builder: (_) => const _PrinterDialog());

class _PrinterDialog extends StatefulWidget {
  const _PrinterDialog();

  @override
  State<_PrinterDialog> createState() => _PrinterDialogState();
}

class _PrinterDialogState extends State<_PrinterDialog> {
  late PrinterConfig _c;
  final _host = TextEditingController();
  final _port = TextEditingController();
  List<BluetoothInfo> _devices = [];
  bool _loading = false;
  bool _testing = false;
  String? _message;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    final saved = PrinterService.instance.config;
    _c = saved != null ? PrinterConfig.fromJson(saved.toJson()) : PrinterConfig.fromPreset(presetById('generic_58'));
    _host.text = _c.host;
    _port.text = '${_c.port}';
    if (_c.connection == 'bluetooth') _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final list = await PrinterService.instance.pairedDevices();
      setState(() => _devices = list);
      if (list.isEmpty) _say('Aucun appareil appairé : appairez l’imprimante dans les réglages Bluetooth d’Android, puis actualisez.', error: true);
    } catch (e) {
      _say(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
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

  Future<void> _test() async {
    _collect();
    setState(() => _testing = true);
    try {
      await PrinterService.instance.printTest(_c);
      _say('Ticket test envoyé. S’il est illisible, essayez un autre modèle ou désactivez les accents.');
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

  @override
  Widget build(BuildContext context) {
    final preset = presetById(_c.presetId);
    return AlertDialog(
      title: const Text('Imprimante ticket'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<String>(
              value: _c.presetId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Modèle'),
              items: [for (final p in printerPresets) DropdownMenuItem(value: p.id, child: Text('${p.label} · ${p.paper} mm'))],
              onChanged: (id) {
                if (id == null) return;
                setState(() => _c.applyPreset(presetById(id)));
                if (_c.connection == 'bluetooth' && _devices.isEmpty) _loadDevices();
              },
            ),
            if (preset.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(preset.note, style: Theme.of(context).textTheme.bodySmall)),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'bluetooth', icon: Icon(Icons.bluetooth), label: Text('Bluetooth')),
                ButtonSegment(value: 'network', icon: Icon(Icons.lan_outlined), label: Text('Réseau / Wi-Fi')),
              ],
              selected: {_c.connection},
              onSelectionChanged: (s) {
                setState(() => _c.connection = s.first);
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
                    decoration: InputDecoration(labelText: _c.address.isNotEmpty && !_devices.any((d) => d.macAdress == _c.address) ? 'Appareil (${_c.deviceName})' : 'Appareil appairé'),
                    items: [for (final d in _devices) DropdownMenuItem(value: d.macAdress, child: Text('${d.name} · ${d.macAdress}', overflow: TextOverflow.ellipsis))],
                    onChanged: (mac) => setState(() {
                      _c.address = mac ?? '';
                      _c.deviceName = _devices.firstWhere((d) => d.macAdress == mac).name;
                    }),
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
                child: DropdownButtonFormField<int>(
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
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _c.cut, onChanged: (v) => setState(() => _c.cut = v), title: const Text('Coupe automatique du papier')),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _c.drawer, onChanged: (v) => setState(() => _c.drawer = v), title: const Text('Ouvrir le tiroir-caisse (paiement espèces)')),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _c.accents, onChanged: (v) => setState(() => _c.accents = v), title: const Text('Imprimer les accents (é, à, ç)'), subtitle: const Text('Désactivez si les accents sortent en symboles bizarres.')),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _c.autoPrint, onChanged: (v) => setState(() => _c.autoPrint = v), title: const Text('Imprimer le ticket après chaque vente')),
            if (_message != null)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(color: _error ? Colors.red.shade50 : Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text(_message!, style: TextStyle(color: _error ? Colors.red.shade800 : Colors.green.shade800)),
              ),
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
          onPressed: _testing ? null : _test,
          icon: _testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.print_outlined),
          label: const Text('Test'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }
}
