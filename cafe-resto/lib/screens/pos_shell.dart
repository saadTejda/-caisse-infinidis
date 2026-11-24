import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../providers/app_providers.dart';
import '../theme/pos_theme.dart';
import 'cash_screen.dart';
import 'device_settings_screen.dart';
import 'host_screen.dart';
import 'pos_screen.dart';

class PosShell extends ConsumerStatefulWidget {
  const PosShell({super.key});

  @override
  ConsumerState<PosShell> createState() => _PosShellState();
}

class _PosShellState extends ConsumerState<PosShell> {
  int _index = 0;
  int _pending = 0;
  int _refreshToken = 0;
  String _userName = 'Caisse';

  @override
  void initState() {
    super.initState();
    _refreshPending();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await ref.read(syncServiceProvider).user();
    final name = user['name'] ?? user['full_name'] ?? user['email'];
    if (!mounted || name == null || '$name'.trim().isEmpty) return;
    setState(() => _userName = '$name'.trim());
  }

  Future<void> _refreshPending() async {
    final count = await ref.read(orderQueueProvider).pendingCount();
    if (mounted) setState(() => _pending = count);
  }

  Future<void> _sync() async {
    final online = ref.read(onlineProvider).valueOrNull ?? true;
    if (!online) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hors ligne — sync impossible')),
      );
      return;
    }
    try {
      final synced = await ref.read(orderQueueProvider).flush();
      await ref.read(syncServiceProvider).bootstrap();
      await _refreshPending();
      await _loadUser();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync OK ($synced vente(s) rejouée(s))')),
      );
      setState(() => _refreshToken++);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync échouée: $e')),
      );
    }
  }

  Future<void> _logout() async {
    try {
      await ref.read(dioProvider).post('/api/v1/auth/token/logout');
    } catch (_) {}
    await ref.read(sessionStoreProvider).clearAuth();
    if (!mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HostScreen()),
      (_) => false,
    );
  }

  void _openPrinters() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DeviceSettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosColors.pos,
      body: IndexedStack(
        index: _index,
        children: [
          PosScreen(
            userName: _userName,
            pendingCount: _pending,
            refreshToken: _refreshToken,
            onCheckoutDone: _refreshPending,
            onOpenDrawer: () => setState(() => _index = 1),
            onBack: _logout,
            onSync: _sync,
            onPrinters: _openPrinters,
          ),
          Column(
            children: [
              Material(
                color: Colors.white,
                child: SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: 56,
                    child: Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _index = 0;
                            _refreshToken++;
                          }),
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: const Text('Retour'),
                        ),
                        const Text(
                          'Tiroir',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Expanded(child: CashScreen()),
            ],
          ),
        ],
      ),
    );
  }
}
