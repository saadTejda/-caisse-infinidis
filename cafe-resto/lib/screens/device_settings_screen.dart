import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../providers/app_providers.dart';
import '../theme/pos_theme.dart';
import 'pos_dialogs.dart';

/// Surcharge locale (adresse BT scannée) au-dessus des réglages web.
class DeviceSettingsScreen extends ConsumerStatefulWidget {
  const DeviceSettingsScreen({super.key});

  @override
  ConsumerState<DeviceSettingsScreen> createState() => _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends ConsumerState<DeviceSettingsScreen> {
  Map<String, dynamic> _settings = {};
  List<BluetoothInfo> _devices = [];
  String? _overrideBt;
  String? _message;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await ref.read(syncServiceProvider).settings();
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _settings = settings;
      _overrideBt = prefs.getString('bt_override');
    });
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _message = null;
    });
    try {
      final bonded = await PrintBluetoothThermal.pairedBluetooths;
      setState(() => _devices = bonded);
    } catch (e) {
      setState(() => _message = 'Scan BT impossible: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _saveOverride(String? mac) async {
    final prefs = await SharedPreferences.getInstance();
    if (mac == null || mac.isEmpty) {
      await prefs.remove('bt_override');
    } else {
      await prefs.setString('bt_override', mac);
    }
    setState(() {
      _overrideBt = mac;
      _message = 'Adresse Bluetooth locale enregistrée.';
    });
  }

  bool _flag(String key) {
    final value = _settings[key];
    return value == true || value == 1 || value == '1' || value == 'true';
  }

  Future<void> _editPrinter(String slot, String title) async {
    var enabled = _flag('pos.${slot}_enabled');
    var name = '${_settings['pos.${slot}_name'] ?? title}';
    var transport = '${_settings['pos.${slot}_transport'] ?? 'wifi'}';
    var host = '${_settings['pos.${slot}_host'] ?? ''}';
    var port = '${_settings['pos.${slot}_port'] ?? '9100'}';
    var width = '${_settings['pos.${slot}_paper_width'] ?? '80'}';
    var bt = '${_settings['pos.${slot}_bt_address'] ?? ''}';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> edit(String label, String current, ValueChanged<String> apply, {bool phone = false}) async {
            final value = await showPosTextPad(context, title: label, initial: current, hint: label, phone: phone);
            if (value != null) setLocal(() => apply(value));
          }

          Widget line(String label, String value, VoidCallback onTap) {
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(label, style: const TextStyle(fontSize: 12, color: PosColors.muted)),
              subtitle: Text(value.isEmpty ? '—' : value, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: onTap,
            );
          }

          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    value: enabled,
                    onChanged: (value) => setLocal(() => enabled = value),
                  ),
                  line('Nom', name, () => edit('Nom', name, (value) => name = value)),
                  Wrap(
                    spacing: 6,
                    children: [
                      ChoiceChip(label: const Text('Wi-Fi'), selected: transport == 'wifi', onSelected: (_) => setLocal(() => transport = 'wifi')),
                      ChoiceChip(label: const Text('Bluetooth'), selected: transport == 'bluetooth', onSelected: (_) => setLocal(() => transport = 'bluetooth')),
                      ChoiceChip(label: const Text('58 mm'), selected: width == '58', onSelected: (_) => setLocal(() => width = '58')),
                      ChoiceChip(label: const Text('80 mm'), selected: width == '80', onSelected: (_) => setLocal(() => width = '80')),
                    ],
                  ),
                  if (transport == 'wifi') ...[
                    line('Adresse IP', host, () => edit('Adresse IP', host, (value) => host = value)),
                    line('Port', port, () => edit('Port', port, (value) => port = value, phone: true)),
                  ] else
                    line('Adresse Bluetooth', bt, () => edit('Bluetooth', bt, (value) => bt = value)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enregistrer')),
            ],
          );
        },
      ),
    );
    if (saved != true) return;
    try {
      await ref.read(dioProvider).put('/api/v1/settings', data: {
        'values': {
          'pos.${slot}_enabled': enabled,
          'pos.${slot}_name': name,
          'pos.${slot}_transport': transport,
          'pos.${slot}_host': host,
          'pos.${slot}_port': int.tryParse(port) ?? 9100,
          'pos.${slot}_paper_width': width,
          'pos.${slot}_bt_address': bt,
        },
      });
      await ref.read(syncServiceProvider).bootstrap();
      await _load();
      if (!mounted) return;
      setState(() => _message = '$title enregistrée.');
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() => _message = apiMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    String value(String key) => '${_settings[key] ?? '—'}';

    return Scaffold(
      appBar: AppBar(title: const Text('Imprimantes appareil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Touchez une imprimante pour choisir le mode, l’adresse et la largeur du papier.',
            style: TextStyle(color: PosColors.muted),
          ),
          const SizedBox(height: 8),
          _tile('Ticket', 'receipt_printer', value('pos.receipt_printer_transport'), value('pos.receipt_printer_host'), value('pos.receipt_printer_paper_width')),
          _tile('Cuisine 1', 'kitchen_printer_1', value('pos.kitchen_printer_1_transport'), value('pos.kitchen_printer_1_host'), value('pos.kitchen_printer_1_paper_width')),
          _tile('Cuisine 2', 'kitchen_printer_2', value('pos.kitchen_printer_2_transport'), value('pos.kitchen_printer_2_host'), value('pos.kitchen_printer_2_paper_width')),
          const Divider(height: 32),
          const Text(
            'Bluetooth local (surcharge)',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            _overrideBt == null || _overrideBt!.isEmpty
                ? 'Aucune surcharge — les adresses web sont utilisées.'
                : 'Surcharge: $_overrideBt',
            style: const TextStyle(color: PosColors.muted),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _scanning ? null : _scan,
            child: Text(_scanning ? 'Scan…' : 'Scanner les appareils appairés'),
          ),
          TextButton(
            onPressed: () => _saveOverride(null),
            child: const Text('Effacer la surcharge'),
          ),
          if (_message != null)
            Text(_message!, style: const TextStyle(color: PosColors.success)),
          ..._devices.map(
            (d) => ListTile(
              title: Text(d.name),
              subtitle: Text(d.macAdress),
              trailing: const Icon(Icons.bluetooth),
              onTap: () => _saveOverride(d.macAdress),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(String title, String slot, String transport, String host, String width) {
    final shown = transport == 'bluetooth' ? '${_settings['pos.${slot}_bt_address'] ?? '—'}' : host;
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text('$transport · $shown · ${width == '—' ? '80' : width} mm'),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => _editPrinter(slot, title),
      ),
    );
  }
}
