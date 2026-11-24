import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../providers/app_providers.dart';
import '../theme/pos_theme.dart';
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
      final token = response.data['data']['token'] as String;
      await ref.read(sessionStoreProvider).setToken(token);
      await ref.read(syncServiceProvider).bootstrap();
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
    return Scaffold(
      backgroundColor: PosColors.sidebar,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                      decoration: const InputDecoration(labelText: 'Mot de passe'),
                      obscureText: true,
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
