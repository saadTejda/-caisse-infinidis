import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../auth/staff_user.dart';
import '../l10n/caisse_text.dart';
import '../providers/app_providers.dart';
import '../theme/pos_theme.dart';
import '../widgets/developer_signature.dart';
import 'host_screen.dart';
import 'pos_shell.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _hidden = true;
  String _host = '';

  @override
  void initState() {
    super.initState();
    _loadHost();
  }

  Future<void> _loadHost() async {
    final host = await ref.read(sessionStoreProvider).getHost();
    if (mounted) setState(() => _host = host ?? '');
  }

  void _openHost() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HostScreen(changing: true)),
    ).then((_) => _loadHost());
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.post(
        '/api/v1/auth/token',
        data: {
          'email': _email.text.trim(),
          'password': _password.text,
        },
      );
      final data = apiMap(response.data);
      final token = '${data['token'] ?? ''}';
      final user = StaffUser.fromJson(data['user'] is Map ? Map<String, dynamic>.from(data['user'] as Map) : const {});
      if (!user.isActive || token.isEmpty) {
        setState(() => _error = tx(ref.read(localeCodeProvider), 'inactive'));
        return;
      }
      await ref.read(sessionStoreProvider).setToken(token);
      await ref.read(sessionStoreProvider).setUser(user);
      ref.read(localeCodeProvider.notifier).state = user.locale;
      ref.read(staffUserProvider.notifier).state = user;
      if (user.can('pos.access')) {
        await ref.read(syncServiceProvider).bootstrap();
      }
      try {
        final me = await ref.read(dioProvider).get('/api/v1/auth/me');
        final fresh = StaffUser.fromJson(apiMap(me.data));
        if (!fresh.isActive) {
          await ref.read(sessionStoreProvider).clearAuth();
          setState(() => _error = tx(user.locale, 'inactive'));
          return;
        }
        await ref.read(sessionStoreProvider).setUser(fresh);
        ref.read(localeCodeProvider.notifier).state = fresh.locale;
        ref.read(staffUserProvider.notifier).state = fresh;
      } catch (_) {}
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PosShell()),
      );
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? ((e.response!.data['message'] ??
                  e.response!.data['errors']?['email']?[0]) ??
              'Connexion impossible.')
          : 'Connexion impossible.';
      setState(() => _error = '$msg');
    } catch (_) {
      setState(() => _error = 'Connexion impossible.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _openHost();
      },
      child: Scaffold(
      backgroundColor: PosColors.sidebar,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: _openHost,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Adresse du serveur'),
                      ),
                    ),
                    const Icon(Icons.point_of_sale, size: 48, color: PosColors.accent),
                    const SizedBox(height: 8),
                    Text(
                      'Connexion',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ouvrez la caisse pour encaisser.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: PosColors.muted),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'E-mail'),
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        suffixIcon: IconButton(
                          tooltip: _hidden ? 'Afficher' : 'Masquer',
                          onPressed: () => setState(() => _hidden = !_hidden),
                          icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        ),
                      ),
                      obscureText: _hidden,
                      onSubmitted: (_) => _login(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: PosColors.danger)),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _busy ? null : _login,
                      child: Text(_busy ? '…' : 'Entrer'),
                    ),
                    if (_host.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _host,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: PosColors.muted, fontSize: 12),
                      ),
                    ],
                    const DeveloperSignature(),
                  ],
                ),
              ),
            ),
          ),
          ),
        ),
      ),
    ),
    );
  }
}
