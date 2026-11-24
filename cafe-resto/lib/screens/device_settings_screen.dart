import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/app_providers.dart';
import '../theme/pos_theme.dart';

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

  @override
  Widget build(BuildContext context) {
    String slot(String key) => '${_settings[key] ?? '—'}';

    return Scaffold(
      appBar: AppBar(title: const Text('Imprimantes appareil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Config serveur (réglages web)',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          _tile('Ticket', slot('pos.receipt_printer_transport'), slot('pos.receipt_printer_host')),
          _tile('Cuisine 1', slot('pos.kitchen_printer_1_transport'), slot('pos.kitchen_printer_1_host')),
          _tile('Cuisine 2', slot('pos.kitchen_printer_2_transport'), slot('pos.kitchen_printer_2_host')),
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

  Widget _tile(String title, String transport, String host) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text('$transport · $host'),
      ),
    );
  }
}
