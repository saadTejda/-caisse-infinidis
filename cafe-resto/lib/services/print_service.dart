import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrinterConfig {
  PrinterConfig({
    required this.enabled,
    required this.name,
    required this.transport,
    required this.profile,
    required this.host,
    required this.port,
    required this.btAddress,
    required this.paperWidth,
  });

  final bool enabled;
  final String name;
  final String transport; // wifi | bluetooth
  final String profile;
  final String host;
  final int port;
  final String btAddress;
  final String paperWidth; // 58 | 80

  factory PrinterConfig.fromSettings(Map<String, dynamic> settings, String slot) {
    bool asBool(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';
    int asInt(dynamic v, int fallback) {
      if (v is int) return v;
      return int.tryParse('$v') ?? fallback;
    }

    return PrinterConfig(
      enabled: asBool(settings['pos.${slot}_enabled']),
      name: '${settings['pos.${slot}_name'] ?? slot}',
      transport: '${settings['pos.${slot}_transport'] ?? 'wifi'}',
      profile: '${settings['pos.${slot}_profile'] ?? 'generic_escpos'}',
      host: '${settings['pos.${slot}_host'] ?? ''}',
      port: asInt(settings['pos.${slot}_port'], 9100),
      btAddress: '${settings['pos.${slot}_bt_address'] ?? ''}',
      paperWidth: '${settings['pos.${slot}_paper_width'] ?? settings['pos.ticket_width'] ?? '80'}',
    );
  }
}

class PrintService {
  /// Builds simple ESC/POS bytes (generic profile).
  Uint8List buildTicket({
    required String title,
    required List<String> lines,
    required String paperWidth,
    String? footer,
  }) {
    final cols = paperWidth == '58' ? 32 : 42;
    final out = BytesBuilder();

    void raw(List<int> bytes) => out.add(bytes);
    void text(String value) {
      raw(latin1.encode('$value\n'));
    }

    void rule() => text('-' * cols);

    // Init + code page
    raw([0x1B, 0x40]);
    raw([0x1B, 0x74, 0x00]);

    // Center bold title
    raw([0x1B, 0x61, 0x01]);
    raw([0x1B, 0x45, 0x01]);
    text(title);
    raw([0x1B, 0x45, 0x00]);
    raw([0x1B, 0x61, 0x00]);
    rule();
    for (final line in lines) {
      text(_wrap(line, cols));
    }
    rule();
    if (footer != null && footer.trim().isNotEmpty) {
      raw([0x1B, 0x61, 0x01]);
      text(footer.trim());
      raw([0x1B, 0x61, 0x00]);
    }
    text('');
    // Feed + cut
    raw([0x1B, 0x64, 0x04]);
    raw([0x1D, 0x56, 0x00]);
    return out.toBytes();
  }

  Future<void> send(PrinterConfig printer, Uint8List bytes) async {
    if (!printer.enabled) {
      return;
    }
    if (printer.transport == 'bluetooth') {
      await _sendBluetooth(printer.btAddress, bytes);
      return;
    }
    await _sendWifi(printer.host, printer.port, bytes);
  }

  Future<void> printSale({
    required Map<String, dynamic> settings,
    required String publicRef,
    required List<Map<String, dynamic>> cartLines,
    required String total,
    required String orderType,
    String? kitchenNote,
  }) async {
    final businessName = '${settings['business.name'] ?? 'Caisse'}';
    final footer = '${settings['business.ticket_footer'] ?? ''}';
    final receiptLines = <String>[
      'Ref: $publicRef',
      'Type: $orderType',
      ...cartLines.map((line) {
        final qty = line['quantity'];
        final name = line['name'];
        final lineTotal = line['line_total'];
        return '$qty x $name  $lineTotal';
      }),
      'TOTAL: $total',
    ];

    final receipt = PrinterConfig.fromSettings(settings, 'receipt_printer');
    final receiptBytes = buildTicket(
      title: businessName,
      lines: receiptLines,
      paperWidth: receipt.paperWidth,
      footer: footer,
    );
    await send(receipt, receiptBytes);

    final kitchenLines = <String>[
      'CUISINE',
      'Ref: $publicRef',
      'Type: $orderType',
      ...cartLines.map((line) => '${line['quantity']} x ${line['name']}'),
      if (kitchenNote != null && kitchenNote.trim().isNotEmpty) 'Note: $kitchenNote',
    ];

    final count = int.tryParse('${settings['pos.kitchen_printers_count'] ?? '1'}') ?? 1;
    final slots = <String>['kitchen_printer_1'];
    if (count >= 2) {
      slots.add('kitchen_printer_2');
    }
    for (final slot in slots) {
      final printer = PrinterConfig.fromSettings(settings, slot);
      final bytes = buildTicket(
        title: printer.name.isEmpty ? 'Cuisine' : printer.name,
        lines: kitchenLines,
        paperWidth: printer.paperWidth,
      );
      await send(printer, bytes);
    }
  }

  Future<void> _sendWifi(String host, int port, Uint8List bytes) async {
    if (host.trim().isEmpty) {
      throw StateError('IP imprimante manquante');
    }
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    try {
      socket.add(bytes);
      await socket.flush();
    } finally {
      await socket.close();
    }
  }

  Future<void> _sendBluetooth(String address, Uint8List bytes) async {
    final prefs = await SharedPreferences.getInstance();
    final override = prefs.getString('bt_override');
    final target = (override != null && override.isNotEmpty) ? override : address;
    if (target.trim().isEmpty) {
      throw StateError('Adresse Bluetooth manquante');
    }
    final connected = await PrintBluetoothThermal.connectionStatus;
    if (!connected) {
      final ok = await PrintBluetoothThermal.connect(macPrinterAddress: target);
      if (!ok) {
        throw StateError('Connexion Bluetooth impossible');
      }
    }
    final written = await PrintBluetoothThermal.writeBytes(bytes);
    if (!written) {
      throw StateError('Écriture Bluetooth échouée');
    }
  }

  String _wrap(String input, int cols) {
    if (input.length <= cols) {
      return input;
    }
    return '${input.substring(0, cols - 1)}…';
  }
}
