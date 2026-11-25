import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../theme/pos_theme.dart';
import '../widgets/developer_signature.dart';
import 'login_screen.dart';

class HostScreen extends ConsumerStatefulWidget {
  const HostScreen({super.key, this.changing = false});

  /// Ouvert depuis la connexion : le retour revient à cette page.
  final bool changing;

  @override
  ConsumerState<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends ConsumerState<HostScreen> {
  final _controller = TextEditingController(text: 'http://192.168.1.10:8000');
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final host = await ref.read(sessionStoreProvider).getHost();
    if (host != null && host.isNotEmpty) {
      _controller.text = host;
    }
  }

  Future<void> _continue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var host = _controller.text.trim();
      if (!host.startsWith('http')) {
        host = 'http://$host';
      }
      host = host.replaceAll(RegExp(r'/+$'), '');
      await ref.read(sessionStoreProvider).setHost(host);

      final dio = Dio(BaseOptions(
        baseUrl: host,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: {'Accept': 'application/json'},
      ));
      // Ping public login route shape (expects 422 without body).
      try {
        await dio.post('/api/v1/auth/token', data: {});
      } on DioException catch (e) {
        if (e.response == null) {
          rethrow;
        }
      }

      if (!mounted) return;
      if (widget.changing) {
        Navigator.of(context).pop();
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } catch (e) {
      setState(() => _error = 'Hôte injoignable. Vérifiez l’URL / le Wi‑Fi.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosColors.sidebar,
      appBar: widget.changing
          ? AppBar(
              title: const Text('Adresse du serveur'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
            )
          : null,
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
                    const Icon(Icons.dns_outlined, size: 48, color: PosColors.accent),
                    const SizedBox(height: 8),
                    Text(
                      'Café Resto',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: PosColors.accent,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choisissez l’adresse de l’API caisse',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: PosColors.muted),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        labelText: 'Hôte API',
                        hintText: 'http://192.168.x.x:8000',
                      ),
                      keyboardType: TextInputType.url,
                      onSubmitted: (_) => _continue(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: PosColors.danger)),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _busy ? null : _continue,
                      child: Text(_busy ? 'Test…' : 'Continuer'),
                    ),
                    const DeveloperSignature(),
                  ],
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
