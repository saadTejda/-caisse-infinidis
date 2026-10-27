import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_state.dart';
import 'printing/printer_service.dart';
import 'ui/login_page.dart';
import 'ui/pos_page.dart';
import 'ui/setup_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.boot();
  await PrinterService.instance.load();
  PrinterService.instance.startWatch();
  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  runApp(PosApp(state: state));
}

class PosApp extends StatelessWidget {
  const PosApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF1F4FD8);
    return MaterialApp(
      title: 'Caisse INFINIDIS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: brand),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
        filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(0, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
        outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
      ),
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          if (!state.hasServer) return const SetupPage();
          if (!state.loggedIn) return const LoginPage();
          return const PosPage();
        },
      ),
    );
  }
}

/// Message court en bas de l'écran.
void toast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? Colors.red.shade700 : null,
    behavior: SnackBarBehavior.floating,
    duration: Duration(seconds: error ? 5 : 3),
  ));
}
