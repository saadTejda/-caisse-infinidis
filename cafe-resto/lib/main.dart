import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'providers/app_providers.dart';
import 'screens/host_screen.dart';
import 'screens/login_screen.dart';
import 'screens/pos_shell.dart';
import 'theme/pos_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: CaisseApp()));
}

class CaisseApp extends ConsumerWidget {
  const CaisseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(localeCodeProvider);
    return MaterialApp(
      title: 'Café Resto Caisse',
      debugShowCheckedModeBanner: false,
      theme: buildPosTheme(),
      locale: Locale(code),
      supportedLocales: const [Locale('fr'), Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Directionality(
          textDirection: code == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const _BootstrapGate(),
    );
  }
}

class _BootstrapGate extends ConsumerStatefulWidget {
  const _BootstrapGate();

  @override
  ConsumerState<_BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends ConsumerState<_BootstrapGate> {
  Widget? _home;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final store = ref.read(sessionStoreProvider);
    final host = await store.getHost();
    final token = await store.getToken();
    Widget next = const HostScreen();
    if (host != null && host.isNotEmpty) {
      if (token != null && token.isNotEmpty) {
        final user = await store.getUser();
        ref.read(localeCodeProvider.notifier).state = user.locale;
        next = const PosShell();
      } else {
        next = const LoginScreen();
      }
    }
    if (mounted) setState(() => _home = next);
  }

  @override
  Widget build(BuildContext context) {
    return _home ??
        const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
  }
}
