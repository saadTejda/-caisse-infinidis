import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../auth/staff_user.dart';
import '../l10n/caisse_text.dart';
import '../providers/app_providers.dart';
import '../services/print_service.dart';
import '../theme/pos_theme.dart';
import '../widgets/pos_status_bar.dart';
import 'business_settings_screen.dart';
import 'cash_screen.dart';
import 'catalog_screen.dart';
import 'dashboard_screen.dart';
import 'deliveries_screen.dart';
import 'device_settings_screen.dart';
import 'host_screen.dart';
import 'orders_screen.dart';
import 'pos_screen.dart';
import 'users_screen.dart';

class PosShell extends ConsumerStatefulWidget {
  const PosShell({super.key});

  @override
  ConsumerState<PosShell> createState() => _PosShellState();
}

class _PosShellState extends ConsumerState<PosShell> {
  int _pending = 0;
  int _errors = 0;
  bool? _sessionOpen;
  int _refreshToken = 0;
  String _module = 'pos';
  StaffUser _user = StaffUser.empty;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    var user = await ref.read(sessionStoreProvider).getUser();
    if (user.permissions.isEmpty && user.roles.isEmpty) {
      final cached = await ref.read(syncServiceProvider).user();
      if (cached.isNotEmpty) user = StaffUser.fromJson(cached);
    }
    ref.read(printServiceProvider).startWatch();
    if (user.permissions.isEmpty && user.roles.isEmpty) {
      try {
        final me = await ref.read(dioProvider).get('/api/v1/auth/me');
        user = StaffUser.fromJson(apiMap(me.data));
        await ref.read(sessionStoreProvider).setUser(user);
      } catch (_) {
        user = const StaffUser(
          id: null,
          name: 'Caisse',
          email: '',
          phone: '',
          locale: 'fr',
          isActive: true,
          roles: ['cashier'],
          permissions: ['dashboard.view', 'pos.access', 'orders.view', 'cash.operate'],
        );
      }
    }
    if (!user.isActive) {
      await _logout();
      return;
    }
    ref.read(localeCodeProvider.notifier).state = user.locale;
    ref.read(staffUserProvider.notifier).state = user;
    final modules = _modulesFor(user);
    if (mounted) {
      setState(() {
        _user = user;
        _module = modules.isEmpty ? '' : modules.first;
      });
    }
    _refreshHeader();
  }

  List<String> _modulesFor(StaffUser user) {
    final modules = <String>[];
    if (user.can('pos.access')) modules.add('pos');
    if (user.can('orders.view')) modules.add('orders');
    if (user.can('cash.operate')) modules.add('cash');
    if (user.can('dashboard.view')) modules.add('dashboard');
    if (user.can('delivery.view')) modules.add('delivery');
    if (user.can('catalog.manage')) modules.add('catalog');
    if (user.can('users.manage')) modules.add('team');
    if (user.can('settings.manage')) modules.add('settings');
    if (user.can('pos.access')) modules.add('printers');
    return modules;
  }

  Future<void> _refreshHeader() async {
    final queue = ref.read(orderQueueProvider);
    final count = await queue.pendingCount();
    final errors = await queue.errorCount();
    final raw = await ref.read(localStoreProvider).getJson('cash_status');
    final open = raw is Map && raw.containsKey('session_open') ? raw['session_open'] == true : null;
    if (mounted) {
      setState(() {
        _pending = count;
        _errors = errors;
        _sessionOpen = open;
      });
    }
  }

  Future<void> _sync() async {
    try {
      final synced = await ref.read(orderQueueProvider).flush();
      if (_user.can('pos.access')) await ref.read(syncServiceProvider).bootstrap();
      await _refreshHeader();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync OK ($synced)')));
      setState(() => _refreshToken++);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync échouée: $error')));
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
    ref.listen(onlineProvider, (previous, next) {
      final was = previous?.valueOrNull ?? false;
      final now = next.valueOrNull ?? false;
      if (now && !was) {
        _sync();
      } else {
        _refreshHeader();
      }
    });
    final code = ref.watch(localeCodeProvider);
    final online = ref.watch(onlineProvider).valueOrNull;
    final modules = _modulesFor(_user);
    if (modules.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tx(code, 'no_module')),
              TextButton(onPressed: _logout, child: Text(tx(code, 'logout'))),
            ],
          ),
        ),
      );
    }
    final selected = modules.indexOf(_module);
    return Scaffold(
      backgroundColor: PosColors.pos,
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: Colors.white,
            selectedIndex: selected < 0 ? 0 : selected,
            onDestinationSelected: (index) {
              setState(() => _module = modules[index]);
              _refreshHeader();
            },
            labelType: NavigationRailLabelType.all,
            leading: InkWell(
              onTap: _logout,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.logout, size: 20),
                    Text(tx(code, 'logout'), style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
            destinations: [
              for (final module in modules) NavigationRailDestination(icon: Icon(_icon(module)), label: Text(tx(code, module == 'printers' ? 'printers' : module))),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _statusBar(online),
                Expanded(child: _module == 'pos' ? _body(modules) : SafeArea(child: _body(modules))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBar(bool? online) {
    final service = ref.watch(printServiceProvider);
    return ValueListenableBuilder<PrinterLink>(
      valueListenable: service.link,
      builder: (context, value, _) {
        return PosStatusBar(
          online: online,
          sessionOpen: _sessionOpen,
          pending: _pending,
          errors: _errors,
          printer: switch (value) {
            PrinterLink.none => PrinterChip.hidden,
            PrinterLink.connecting => PrinterChip.connecting,
            PrinterLink.connected => PrinterChip.ready,
            PrinterLink.offline => PrinterChip.down,
          },
        );
      },
    );
  }

  Widget _body(List<String> modules) {
    final code = ref.watch(localeCodeProvider);
    if (modules.isEmpty) {
      return Center(child: Text(tx(code, 'no_module')));
    }
    return switch (_module) {
      'orders' => OrdersScreen(user: _user),
      'cash' => const CashScreen(),
      'dashboard' => const DashboardScreen(),
      'delivery' => DeliveriesScreen(user: _user),
      'catalog' => const CatalogScreen(),
      'team' => const UsersScreen(),
      'settings' => const BusinessSettingsScreen(),
      'printers' => const DeviceSettingsScreen(),
      _ => PosScreen(
          userName: _user.name.isEmpty ? 'Caisse' : _user.name,
          pendingCount: _pending,
          refreshToken: _refreshToken,
          onCheckoutDone: _refreshHeader,
          onOpenDrawer: _user.can('cash.operate') ? () => setState(() => _module = 'cash') : null,
          onBack: _logout,
          onSync: _sync,
          onPrinters: () => setState(() => _module = 'printers'),
        ),
    };
  }

  IconData _icon(String module) {
    return switch (module) {
      'orders' => Icons.receipt_long,
      'cash' => Icons.point_of_sale,
      'dashboard' => Icons.insights,
      'delivery' => Icons.delivery_dining,
      'catalog' => Icons.restaurant_menu,
      'team' => Icons.group,
      'settings' => Icons.tune,
      'printers' => Icons.print,
      _ => Icons.storefront,
    };
  }
}
