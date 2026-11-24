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

  @override
  void initState() {
    super.initState();
    _refreshPending();
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync OK ($synced vente(s) rejouée(s))')),
      );
      setState(() {});
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

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(onlineProvider).valueOrNull ?? true;

    return Scaffold(
      appBar: AppBar(
        title: Text(_index == 0 ? 'Caisse' : 'Tiroir'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: online ? PosColors.success : PosColors.danger,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  online ? 'En ligne' : 'Hors ligne',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          if (_pending > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(
                  '$_pending en attente',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Synchroniser',
            onPressed: _sync,
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Imprimantes',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DeviceSettingsScreen()),
              );
            },
            icon: const Icon(Icons.print),
          ),
          IconButton(
            tooltip: 'Quitter',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          PosScreen(onCheckoutDone: _refreshPending),
          const CashScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'Caisse'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: 'Tiroir'),
        ],
      ),
    );
  }
}
