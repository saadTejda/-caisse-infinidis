import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'ticket_printer.dart';

/// Config des tickets de cette tablette. Vide tant que le commerçant n’a rien enregistré :
/// l’impression continue alors avec les réglages du serveur.
class TicketPrinterStore {
  static const storageKey = 'ticket_printers_v1';

  Future<Map<String, TicketPrinter>?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final out = <String, TicketPrinter>{};
    for (final role in ticketPrinterRoles.keys) {
      final value = decoded[role];
      if (value is Map) {
        out[role] = TicketPrinter.fromJson(Map<String, dynamic>.from(value));
      }
    }
    return out.isEmpty ? null : out;
  }

  Future<void> write(Map<String, TicketPrinter> printers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode({for (final entry in printers.entries) entry.key: entry.value.toJson()}),
    );
  }

  /// Réglages serveur utilisés seulement s’il n’y a encore rien sur la tablette.
  Future<Map<String, TicketPrinter>> loadOrSeed(Map<String, dynamic> settings) async {
    final saved = await read();
    if (saved != null) return saved;
    return {
      for (final role in ticketPrinterRoles.keys) role: TicketPrinter.fromServer(settings, role),
    };
  }
}
