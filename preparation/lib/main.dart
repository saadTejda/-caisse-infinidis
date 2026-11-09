import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_state.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';
import 'ui/setup_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.boot();
  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  runApp(PrepApp(state: state));
}

class PrepApp extends StatelessWidget {
  const PrepApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF059669);
    return MaterialApp(
      title: 'Préparation INFINIDIS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: brand, primary: brand),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
        filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(0, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
        outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
      ),
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          if (!state.hasServer) return const SetupPage();
          if (!state.loggedIn) return const LoginPage();
          return const HomePage();
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
