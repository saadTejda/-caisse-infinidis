import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../theme/pos_theme.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  List<Map<String, dynamic>> _users = [];
  List<String> _roles = const ['manager', 'cashier', 'waiter', 'driver', 'kitchen'];
  String? _error;
  bool _busy = false;

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
      final response = await ref.read(dioProvider).get('/api/v1/users');
      final body = response.data;
      final roles = body is Map && body['assignable_roles'] is List
          ? (body['assignable_roles'] as List).map((role) => '$role').toList()
          : _roles;
      setState(() {
        _users = apiList(body);
        if (roles.isNotEmpty) _roles = roles;
      });
    } on DioException catch (error) {
      setState(() => _error = apiMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? user]) async {
    final name = TextEditingController(text: '${user?['name'] ?? ''}');
    final email = TextEditingController(text: '${user?['email'] ?? ''}');
    final phone = TextEditingController(text: '${user?['phone'] ?? ''}');
    final password = TextEditingController();
    var role = user == null
        ? _roles.first
        : ((user['roles'] is List && (user['roles'] as List).isNotEmpty) ? '${(user['roles'] as List).first}' : _roles.first);
    if (!_roles.contains(role)) role = _roles.first;
    var locale = '${user?['locale'] ?? 'fr'}';
    var active = user?['is_active'] != false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(user == null ? 'Compte' : '${user['name']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom')),
                TextField(
                  controller: email,
                  enabled: user == null,
                  decoration: InputDecoration(
                    labelText: 'E-mail',
                    helperText: user == null ? null : 'E-mail fixé à la création.',
                  ),
                ),
                TextField(controller: phone, decoration: const InputDecoration(labelText: 'Téléphone')),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: InputDecoration(labelText: user == null ? 'Mot de passe' : 'Nouveau mot de passe'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  items: [for (final item in _roles) DropdownMenuItem(value: item, child: Text(item))],
                  onChanged: (value) => setLocal(() => role = value ?? role),
                ),
                DropdownButtonFormField<String>(
                  initialValue: const ['fr', 'ar', 'en'].contains(locale) ? locale : 'fr',
                  items: const [
                    DropdownMenuItem(value: 'fr', child: Text('Français')),
                    DropdownMenuItem(value: 'ar', child: Text('العربية')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: (value) => setLocal(() => locale = value ?? locale),
                ),
                if (user != null)
                  SwitchListTile(
                    value: active,
                    title: const Text('Actif'),
                    onChanged: (value) => setLocal(() => active = value),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (name.text.trim().isEmpty) return;
    if (user == null && (email.text.trim().isEmpty || password.text.trim().length < 8)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nom, e-mail et mot de passe (8 caractères) sont obligatoires.')),
      );
      return;
    }
    try {
      final dio = ref.read(dioProvider);
      if (user == null) {
        await dio.post('/api/v1/users', data: {
          'name': name.text.trim(),
          'email': email.text.trim(),
          'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
          'locale': locale,
          'role': role,
          'password': password.text,
        });
      } else {
        await dio.patch('/api/v1/users/${user['id']}', data: {
          'name': name.text.trim(),
          'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
          'locale': locale,
          'role': role,
          'is_active': active,
          if (password.text.isNotEmpty) 'password': password.text,
        });
      }
      await _load();
    } on DioException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(onPressed: () => _edit(), child: const Text('Nouveau compte')),
        ),
        if (_error != null) Text(_error!, style: const TextStyle(color: PosColors.danger)),
        if (_busy) const LinearProgressIndicator(),
        for (final user in _users)
          ListTile(
            title: Text('${user['name']}'),
            subtitle: Text('${user['email']} · ${(user['roles'] as List?)?.join(', ') ?? ''} · ${user['locale'] ?? 'fr'}'),
            trailing: Icon(
              user['is_active'] == false ? Icons.block : Icons.check_circle_outline,
              color: user['is_active'] == false ? PosColors.danger : PosColors.success,
            ),
            onTap: () => _edit(user),
          ),
      ],
    );
  }
}
