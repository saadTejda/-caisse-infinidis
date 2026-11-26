import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../printing/ticket_printer.dart';
import '../printing/ticket_printer_store.dart';
import '../providers/app_providers.dart';
import '../services/print_service.dart';
import '../theme/pos_theme.dart';

const _roleLabels = {
  'receipt': 'Ticket de caisse',
  'kitchen1': 'Cuisine 1',
  'kitchen2': 'Cuisine 2',
};

/// Réglage des tickets de cette tablette : choix simple, puis détails repliés.
class DeviceSettingsScreen extends ConsumerStatefulWidget {
  const DeviceSettingsScreen({super.key});

  @override
  ConsumerState<DeviceSettingsScreen> createState() => _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends ConsumerState<DeviceSettingsScreen> {
  final _store = TicketPrinterStore();
  Map<String, TicketPrinter> _printers = {};
  String? _message;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await ref.read(syncServiceProvider).settings();
    final printers = await _store.loadOrSeed(settings);
    if (!mounted) return;
    setState(() {
      _printers = printers;
      _busy = false;
    });
  }

  Widget _linkLine() {
    final service = ref.watch(printServiceProvider);
    return ValueListenableBuilder<PrinterLink>(
      valueListenable: service.link,
      builder: (context, value, _) => Text(printerLinkLabel(value), style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Future<void> _open(String role) async {
    final current = _printers[role] ?? TicketPrinter.fromPreset(presetById('generic_80'), role: role);
    final edited = await Navigator.of(context).push<TicketPrinter>(
      MaterialPageRoute(builder: (_) => _PrinterEditor(title: _roleLabels[role] ?? role, printer: TicketPrinter.fromJson(current.toJson()))),
    );
    if (edited == null) return;
    final next = Map<String, TicketPrinter>.from(_printers);
    next[role] = edited;
    await _store.write(next);
    await ref.read(printServiceProvider).startWatch();
    if (!mounted) return;
    setState(() {
      _printers = next;
      _message = '${_roleLabels[role]} enregistrée sur cette tablette.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Imprimantes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Chaque tablette garde ses propres imprimantes. Choisissez l’appareil, le modèle se règle tout seul.',
            style: TextStyle(color: PosColors.muted),
          ),
          const SizedBox(height: 8),
          _linkLine(),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(_message!, style: const TextStyle(color: PosColors.success)),
          ],
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          for (final role in ticketPrinterRoles.keys)
            Card(
              child: ListTile(
                title: Text(_roleLabels[role] ?? role),
                subtitle: Text(
                  _printers[role]?.summary ?? 'Pas encore réglée',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy ? null : () => _open(role),
              ),
            ),
        ],
      ),
    );
  }
}

class _PrinterEditor extends StatefulWidget {
  const _PrinterEditor({required this.title, required this.printer});

  final String title;
  final TicketPrinter printer;

  @override
  State<_PrinterEditor> createState() => _PrinterEditorState();
}

class _PrinterEditorState extends State<_PrinterEditor> {
  late final TicketPrinter _printer = widget.printer;
  late String _brand = presetById(_printer.presetId).brand;
  final _host = TextEditingController();
  final _port = TextEditingController();
  List<BluetoothInfo> _devices = [];
  bool _loading = false;
  bool _testing = false;
  bool _asked = false;
  String? _message;
  bool _error = false;
  static const _pages = [16, 2, 19, 0];
  static const _cuts = ['feed', 'full', 'partial'];

  @override
  void initState() {
    super.initState();
    _host.text = _printer.host;
    _port.text = '${_printer.port}';
    if (_printer.connection == 'bluetooth') _loadDevices();
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  List<PrinterPreset> get _models => printerPresets.where((preset) => preset.brand == _brand).toList();

  void _say(String message, {bool error = false}) {
    setState(() {
      _message = message;
      _error = error;
    });
  }

  Future<void> _loadDevices() async {
    setState(() => _loading = true);
    try {
      final list = await PrintBluetoothThermal.pairedBluetooths;
      if (!mounted) return;
      setState(() => _devices = list);
      if (list.isEmpty) {
        _say('Aucun appareil appairé. Allumez l’imprimante, appairez-la dans les réglages Bluetooth d’Android, puis actualisez.', error: true);
      }
    } catch (_) {
      _say('Impossible de lire les appareils Bluetooth. Vérifiez que le Bluetooth de la tablette est allumé.', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pickDevice(BluetoothInfo device) {
    final found = detectPreset(device.name);
    setState(() {
      _printer.address = device.macAdress;
      _printer.deviceName = device.name;
      if (found != null) {
        _printer.applyPreset(found);
        _brand = found.brand;
        _say('Modèle reconnu : ${found.label}. Papier ${found.paper} mm.');
        _error = false;
      } else {
        _say('Modèle non reconnu. Choisissez la marque, ou gardez « Autre imprimante ».');
        _error = false;
      }
    });
  }

  void _applyModel(String id) {
    final preset = presetById(id);
    setState(() => _printer.applyPreset(preset));
  }

  Future<void> _test({String? note}) async {
    _printer.host = _host.text.trim();
    _printer.port = int.tryParse(_port.text.trim()) ?? 9100;
    setState(() => _testing = true);
    try {
      await PrintService().printTest(_printer);
      if (!mounted) return;
      setState(() => _asked = true);
      _say('${note == null ? '' : '$note\n'}Ticket test imprimé. Regardez-le et répondez ci-dessous.');
    } catch (error) {
      _say('$error', error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _fixAccents() {
    String note;
    if (!_printer.accents) {
      _printer.accents = true;
      _printer.codePage = _pages.first;
      note = 'Nouvel essai des accents.';
    } else {
      final index = _pages.indexOf(_printer.codePage);
      if (index + 1 < _pages.length) {
        _printer.codePage = _pages[index + 1];
        note = 'Autre page d’accents : ${codePages[_printer.codePage]}.';
      } else {
        _printer.accents = false;
        note = 'Accents retirés : é devient e. Le ticket reste lisible.';
      }
    }
    setState(() {});
    _test(note: note);
  }

  void _fixCut() {
    String note;
    if (!_printer.cut) {
      _printer.cut = true;
      _printer.cutMode = _cuts.first;
      note = 'Coupe activée : ${cutModes[_printer.cutMode]}.';
    } else {
      final index = _cuts.indexOf(_printer.cutMode);
      if (index + 1 < _cuts.length) {
        _printer.cutMode = _cuts[index + 1];
        note = 'Autre façon de couper : ${cutModes[_printer.cutMode]}.';
      } else {
        _printer.cut = false;
        _printer.cutMode = 'none';
        note = 'Cette imprimante ne coupe pas. Déchirez le ticket.';
      }
    }
    setState(() {});
    _test(note: note);
  }

  void _fixWidth({required bool tooWide}) {
    const steps = [32, 42, 48];
    final index = steps.indexOf(_printer.columns);
    if (tooWide) {
      if (_printer.paper >= 80 && index > 0) {
        _printer.columns = steps[index - 1];
      } else {
        _printer.paper = 58;
        _printer.columns = 32;
      }
    } else if (_printer.paper < 80) {
      _printer.paper = 80;
      _printer.columns = 42;
    } else {
      _printer.columns = index >= 0 && index + 1 < steps.length ? steps[index + 1] : 48;
    }
    setState(() {});
    _test(note: 'Largeur réglée : ${_printer.paper} mm, ${_printer.columns} caractères par ligne.');
  }

  void _save() {
    _printer.host = _host.text.trim();
    _printer.port = int.tryParse(_port.text.trim()) ?? 9100;
    if (_printer.connection == 'network' && _printer.host.isEmpty) {
      _say('Saisissez l’adresse IP de l’imprimante.', error: true);
      return;
    }
    if (_printer.connection == 'bluetooth' && _printer.address.isEmpty) {
      _say('Choisissez l’imprimante Bluetooth.', error: true);
      return;
    }
    Navigator.of(context).pop(_printer);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Utiliser cette imprimante'),
            value: _printer.enabled,
            onChanged: (value) => setState(() => _printer.enabled = value),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _mode('Bluetooth', 'bluetooth'),
              const SizedBox(width: 8),
              _mode('Réseau', 'network'),
            ],
          ),
          const SizedBox(height: 12),
          if (_printer.connection == 'bluetooth') ...[
            OutlinedButton.icon(
              onPressed: _loading ? null : _loadDevices,
              icon: const Icon(Icons.bluetooth),
              label: Text(_loading ? 'Recherche…' : 'Appareils appairés'),
            ),
            for (final device in _devices)
              ListTile(
                dense: true,
                selected: device.macAdress == _printer.address,
                title: Text(device.name),
                subtitle: Text(device.macAdress),
                onTap: () => _pickDevice(device),
              ),
          ] else ...[
            TextField(
              controller: _host,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Adresse IP', hintText: '192.168.1.40'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port', hintText: '9100'),
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _brand,
            decoration: const InputDecoration(labelText: 'Marque'),
            items: [for (final brand in printerBrands) DropdownMenuItem(value: brand, child: Text(brand))],
            onChanged: (brand) {
              if (brand == null) return;
              final models = printerPresets.where((preset) => preset.brand == brand).toList();
              setState(() {
                _brand = brand;
                if (models.isNotEmpty) _printer.applyPreset(models.first);
              });
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _models.any((preset) => preset.id == _printer.presetId) ? _printer.presetId : _models.first.id,
            decoration: const InputDecoration(labelText: 'Modèle'),
            items: [for (final preset in _models) DropdownMenuItem(value: preset.id, child: Text(preset.model, overflow: TextOverflow.ellipsis))],
            onChanged: (id) {
              if (id != null) _applyModel(id);
            },
          ),
          if (presetById(_printer.presetId).note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(presetById(_printer.presetId).note, style: const TextStyle(color: PosColors.muted, fontSize: 12)),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              _paper(58),
              const SizedBox(width: 8),
              _paper(80),
            ],
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Réglages avancés'),
            children: [
              _number('Caractères par ligne', _printer.columns, [32, 42, 48], (value) => _printer.columns = value),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Couper le papier'),
                value: _printer.cut,
                onChanged: (value) => setState(() {
                  _printer.cut = value;
                  if (!value) _printer.cutMode = 'none';
                  if (value && _printer.cutMode == 'none') _printer.cutMode = 'feed';
                }),
              ),
              if (_printer.cut)
                DropdownButtonFormField<String>(
                  initialValue: cutModes.containsKey(_printer.cutMode) ? _printer.cutMode : 'feed',
                  decoration: const InputDecoration(labelText: 'Mode de coupe'),
                  items: [for (final entry in cutModes.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value))],
                  onChanged: (value) => setState(() => _printer.cutMode = value ?? 'feed'),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ouvrir le tiroir'),
                value: _printer.drawer,
                onChanged: (value) => setState(() => _printer.drawer = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Imprimer les accents'),
                subtitle: const Text('Sinon é devient e'),
                value: _printer.accents,
                onChanged: (value) => setState(() => _printer.accents = value),
              ),
              if (_printer.accents)
                DropdownButtonFormField<int>(
                  initialValue: codePages.containsKey(_printer.codePage) ? _printer.codePage : 16,
                  decoration: const InputDecoration(labelText: 'Page des accents'),
                  items: [for (final entry in codePages.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value))],
                  onChanged: (value) => setState(() => _printer.codePage = value ?? 16),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Code-barres du ticket'),
                value: _printer.barcode,
                onChanged: (value) => setState(() => _printer.barcode = value),
              ),
              _number('Copies', _printer.copies, [1, 2, 3], (value) => _printer.copies = value),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Imprimer après chaque vente'),
                value: _printer.autoPrint,
                onChanged: (value) => setState(() => _printer.autoPrint = value),
              ),
              if (_printer.connection == 'bluetooth')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Garder la liaison'),
                  value: _printer.keepAlive,
                  onChanged: (value) => setState(() => _printer.keepAlive = value),
                ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(_message!, style: TextStyle(color: _error ? PosColors.danger : PosColors.ink)),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _testing ? null : _test,
            icon: const Icon(Icons.print_outlined),
            label: Text(_testing ? 'Impression…' : 'Imprimer un test'),
          ),
          if (_asked) ...[
            const SizedBox(height: 10),
            const Text('Le ticket test est-il correct ?', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Chaque bouton corrige et réimprime.', style: TextStyle(color: PosColors.muted, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _fix('Accents illisibles', _fixAccents),
                _fix('La coupe ne part pas', _fixCut),
                _fix('Le texte dépasse', () => _fixWidth(tooWide: true)),
                _fix('Le texte est trop étroit', () => _fixWidth(tooWide: false)),
                _fix('Le code-barres est illisible', () {
                  setState(() => _printer.barcode = false);
                  _test(note: 'Le numéro est imprimé en texte, sans code-barres.');
                }),
              ],
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF111827), minimumSize: const Size.fromHeight(44)),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  Widget _fix(String label, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: _testing ? null : onTap,
      child: Text(label),
    );
  }

  Widget _mode(String label, String value) {
    final selected = _printer.connection == value;
    return Expanded(
      child: Material(
        color: selected ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() {
            _printer.connection = value;
            if (value == 'bluetooth' && _devices.isEmpty) _loadDevices();
          }),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: selected ? const Color(0xFF111827) : PosColors.line),
            ),
            child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: selected ? Colors.white : PosColors.ink)),
          ),
        ),
      ),
    );
  }

  Widget _paper(int width) {
    final selected = _printer.paper == width;
    return Expanded(
      child: OutlinedButton(
        onPressed: () => setState(() {
          _printer.paper = width;
          _printer.columns = width >= 80 ? 48 : 32;
        }),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? const Color(0xFF111827) : Colors.white,
          foregroundColor: selected ? Colors.white : PosColors.ink,
          minimumSize: const Size(0, 40),
        ),
        child: Text('$width mm'),
      ),
    );
  }

  Widget _number(String label, int current, List<int> values, ValueChanged<int> onChanged) {
    final value = values.contains(current) ? current : values.first;
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [for (final item in values) DropdownMenuItem(value: item, child: Text('$item'))],
      onChanged: (next) {
        if (next != null) setState(() => onChanged(next));
      },
    );
  }
}
