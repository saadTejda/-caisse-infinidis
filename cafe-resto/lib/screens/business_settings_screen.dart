import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../theme/pos_theme.dart';

class BusinessSettingsScreen extends ConsumerStatefulWidget {
  const BusinessSettingsScreen({super.key});

  @override
  ConsumerState<BusinessSettingsScreen> createState() => _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState extends ConsumerState<BusinessSettingsScreen> {
  Map<String, dynamic> _values = {};
  Map<String, dynamic> _definitions = {};
  String? _error;
  bool _busy = false;

  static const _groups = ['business', 'pos', 'cash', 'delivery'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await ref.read(dioProvider).get('/api/v1/settings');
      final body = response.data is Map ? Map<String, dynamic>.from(response.data as Map) : <String, dynamic>{};
      setState(() {
        _values = body['values'] is Map ? Map<String, dynamic>.from(body['values'] as Map) : {};
        _definitions = body['definitions'] is Map ? Map<String, dynamic>.from(body['definitions'] as Map) : {};
      });
    } on DioException catch (error) {
      setState(() => _error = apiMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(String key, dynamic value) async {
    try {
      final response = await ref.read(dioProvider).put('/api/v1/settings', data: {
        'values': {key: value},
      });
      final body = response.data is Map ? Map<String, dynamic>.from(response.data as Map) : <String, dynamic>{};
      if (body['values'] is Map) {
        setState(() => _values = Map<String, dynamic>.from(body['values'] as Map));
      }
    } on DioException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiMessage(error))));
    }
  }

  Future<void> _logo() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;
    try {
      final form = FormData.fromMap({
        'logo': await MultipartFile.fromFile(file.path, filename: file.name),
      });
      await ref.read(dioProvider).post('/api/v1/settings/logo', data: form);
      await _load();
    } on DioException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiMessage(error))));
    }
  }

  Future<void> _clearLogo() async {
    try {
      await ref.read(dioProvider).delete('/api/v1/settings/logo');
      await _load();
    } on DioException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = _definitions.keys.where((key) {
      final definition = _definitions[key];
      if (definition is! Map) return false;
      return _groups.contains(definition['group']);
    }).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null) Text(_error!, style: const TextStyle(color: PosColors.danger)),
        if (_busy) const LinearProgressIndicator(),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(onPressed: _logo, child: const Text('Logo')),
            TextButton(onPressed: _clearLogo, child: const Text('Retirer le logo')),
          ],
        ),
        if ('${_values['business.logo_url'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Image.network('${_values['business.logo_url']}', height: 64, errorBuilder: (context, error, stack) => const SizedBox.shrink()),
          ),
        for (final key in keys) _field(key, Map<String, dynamic>.from(_definitions[key] as Map)),
      ],
    );
  }

  Widget _field(String key, Map<String, dynamic> definition) {
    final value = _values[key] ?? definition['default'];
    final type = '${definition['type']}';
    if (type == 'boolean') {
      final enabled = value == true || value == 1 || value == '1' || value == 'true';
      return SwitchListTile(
        title: Text(key),
        value: enabled,
        onChanged: (next) => _save(key, next),
      );
    }
    if (type == 'enum') {
      final options = definition['options'] is List ? (definition['options'] as List).map((item) => '$item').toList() : <String>[];
      final current = options.contains('$value') ? '$value' : (options.isEmpty ? null : options.first);
      return DropdownButtonFormField<String>(
        initialValue: current,
        decoration: InputDecoration(labelText: key),
        items: [for (final option in options) DropdownMenuItem(value: option, child: Text(option))],
        onChanged: (next) {
          if (next != null) _save(key, next);
        },
      );
    }
    return ListTile(
      title: Text(key),
      subtitle: Text('${value ?? ''}'),
      onTap: () async {
        final controller = TextEditingController(text: '${value ?? ''}');
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(key),
            content: TextField(controller: controller),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enregistrer')),
            ],
          ),
        );
        if (ok != true) return;
        final text = controller.text.trim();
        if (type == 'integer') {
          await _save(key, int.tryParse(text) ?? 0);
        } else if (type == 'percent') {
          await _save(key, double.tryParse(text.replaceAll(',', '.')) ?? 0);
        } else {
          await _save(key, text);
        }
      },
    );
  }
}
