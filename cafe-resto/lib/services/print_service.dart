import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../printing/ticket_builder.dart';
import '../printing/ticket_printer.dart';
import '../printing/ticket_printer_store.dart';

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

enum PrinterLink { none, connecting, connected, offline }

String printerLinkLabel(PrinterLink value) {
  switch (value) {
    case PrinterLink.none:
      return 'Aucune imprimante';
    case PrinterLink.connecting:
      return 'Connexion…';
    case PrinterLink.connected:
      return 'Connectée';
    case PrinterLink.offline:
      return 'Hors ligne. Allumez l’imprimante et vérifiez l’appairage.';
  }
}

class PrintService with WidgetsBindingObserver {
  final link = ValueNotifier<PrinterLink>(PrinterLink.none);
  Timer? _watch;
  String? _linkedAddress;
  bool _observing = false;
  bool _connecting = false;
  bool _sending = false;
  TicketPrinter? _watched;

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
    String? taxLine,
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
      if (taxLine != null && taxLine.isNotEmpty) taxLine,
      'TOTAL: $total',
    ];

    final local = await _localPrinters();
    final autoPrint = settings['pos.auto_print'] == true ||
        settings['pos.auto_print'] == 1 ||
        settings['pos.auto_print'] == '1' ||
        settings['pos.auto_print'] == 'true';
    final localReceipt = local?['receipt'];
    if (localReceipt != null) {
      if (localReceipt.enabled && localReceipt.autoPrint) {
        await _sendQuiet(() => _sendLocal(localReceipt, _localTicket(localReceipt, title: businessName, lines: receiptLines, footer: footer, reference: publicRef)));
      }
    } else if (autoPrint) {
      final receipt = PrinterConfig.fromSettings(settings, 'receipt_printer');
      final receiptBytes = buildTicket(
        title: businessName,
        lines: receiptLines,
        paperWidth: receipt.paperWidth,
        footer: footer,
      );
      await _sendQuiet(() => send(receipt, receiptBytes));
    }

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
      final role = slot == 'kitchen_printer_1' ? 'kitchen1' : 'kitchen2';
      final localKitchen = local?[role];
      if (local != null) {
        if (localKitchen != null && localKitchen.enabled) {
          await _sendQuiet(
            () => _sendLocal(
              localKitchen,
              _localTicket(
                localKitchen,
                title: localKitchen.deviceName.isEmpty ? 'Cuisine' : localKitchen.deviceName,
                lines: kitchenLines,
              ),
            ),
          );
        }
        continue;
      }
      final printer = PrinterConfig.fromSettings(settings, slot);
      final bytes = buildTicket(
        title: printer.name.isEmpty ? 'Cuisine' : printer.name,
        lines: kitchenLines,
        paperWidth: printer.paperWidth,
      );
      await _sendQuiet(() => send(printer, bytes));
    }
  }

  Future<Map<String, TicketPrinter>?> _localPrinters() async {
    try {
      return await TicketPrinterStore().read();
    } catch (_) {
      return null;
    }
  }

  Uint8List _localTicket(
    TicketPrinter printer, {
    required String title,
    required List<String> lines,
    String? footer,
    String? reference,
  }) {
    final ticket = TicketBuilder(printer)..init();
    ticket.text(title, alignTo: 'center', strong: true);
    ticket.hr();
    for (final line in lines) {
      ticket.wrap(line);
    }
    if (reference != null && printer.barcode) {
      ticket.barcode(reference);
    }
    ticket.hr();
    if (footer != null && footer.trim().isNotEmpty) ticket.text(footer.trim(), alignTo: 'center');
    ticket.feed(3);
    if (printer.cut) ticket.cut();
    return Uint8List.fromList(ticket.bytes);
  }

  Future<void> printTest(TicketPrinter printer) async {
    if (printer.connection == 'network' && printer.host.trim().isEmpty) {
      throw PrintFailure('Saisissez l’adresse IP de l’imprimante.');
    }
    if (printer.connection == 'bluetooth' && printer.address.trim().isEmpty) {
      throw PrintFailure('Choisissez d’abord l’imprimante Bluetooth.');
    }
    final ticket = TicketBuilder(printer)..init();
    ticket.text('Café Resto', alignTo: 'center', strong: true);
    ticket.text('Ticket test', alignTo: 'center');
    ticket.hr();
    ticket.wrap(presetById(printer.presetId).label);
    ticket.pair('Papier', '${printer.paper} mm');
    ticket.pair('Caractères / ligne', '${printer.columns}');
    ticket.hr();
    ticket.text('1. Accents : é è ê à â ç ô û É À Ç');
    ticket.text('2. Cette ligne doit tenir sur une seule ligne :');
    ticket.text(List.generate(printer.columns, (index) => '${(index + 1) % 10}').join());
    ticket.text('3. Code-barres :');
    ticket.barcode('TEST-123456');
    ticket.pair('4. Total', '123,45', strong: true);
    ticket.feed(3);
    if (printer.cut) ticket.cut();
    try {
      if (printer.connection == 'bluetooth') {
        await _sendBluetooth(printer.address, Uint8List.fromList(ticket.bytes), useOverride: false);
      } else {
        await _sendWifi(printer.host, printer.port, Uint8List.fromList(ticket.bytes));
      }
      link.value = PrinterLink.connected;
    } on SocketException {
      link.value = PrinterLink.offline;
      throw PrintFailure('Imprimante injoignable. Allumez-la, rapprochez-la, et vérifiez l’adresse ou l’appairage.');
    } catch (error) {
      link.value = PrinterLink.offline;
      final message = '$error';
      if (message.contains('Bluetooth') || message.contains('IP')) {
        throw PrintFailure('Imprimante injoignable. Allumez-la, rapprochez-la, et vérifiez l’adresse ou l’appairage.');
      }
      rethrow;
    }
  }

  Future<void> _sendLocal(TicketPrinter printer, Uint8List bytes) async {
    final copies = printer.copies.clamp(1, 3);
    for (var copy = 0; copy < copies; copy++) {
      if (printer.connection == 'bluetooth') {
        await _sendBluetooth(printer.address, bytes, useOverride: false);
      } else {
        await _sendWifi(printer.host, printer.port, bytes);
      }
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

  Future<void> _sendBluetooth(String address, Uint8List bytes, {bool useOverride = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final override = useOverride ? prefs.getString('bt_override') : null;
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

  Future<void> startWatch() async {
    _watch?.cancel();
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    final local = await _localPrinters();
    _watched = _primary(local);
    final printer = _watched;
    if (printer == null || !printer.enabled || !printer.ready) {
      link.value = PrinterLink.none;
      return;
    }
    if (printer.connection == 'network') {
      link.value = PrinterLink.connected;
      return;
    }
    if (!printer.keepAlive) {
      link.value = PrinterLink.offline;
      return;
    }
    _watch = Timer.periodic(const Duration(seconds: 15), (_) => check());
    await check();
  }

  TicketPrinter? _primary(Map<String, TicketPrinter>? local) {
    if (local == null) return null;
    for (final role in const ['receipt', 'kitchen1', 'kitchen2']) {
      final printer = local[role];
      if (printer != null && printer.enabled && printer.ready && printer.connection == 'bluetooth') return printer;
    }
    for (final role in const ['receipt', 'kitchen1', 'kitchen2']) {
      final printer = local[role];
      if (printer != null && printer.enabled && printer.ready) return printer;
    }
    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }

  Future<void> check() async {
    final printer = _watched;
    if (printer == null || !printer.keepAlive || printer.connection != 'bluetooth' || _connecting || _sending) return;
    try {
      if (!await PrintBluetoothThermal.bluetoothEnabled) {
        link.value = PrinterLink.offline;
        return;
      }
      if (await PrintBluetoothThermal.connectionStatus && _linkedAddress == printer.address) {
        link.value = PrinterLink.connected;
        return;
      }
      await _connectQuiet(printer.address);
    } catch (_) {
      link.value = PrinterLink.offline;
    }
  }

  Future<void> _connectQuiet(String address) async {
    _connecting = true;
    link.value = PrinterLink.connecting;
    try {
      if (await PrintBluetoothThermal.connectionStatus) {
        await PrintBluetoothThermal.disconnect;
      }
      final ok = await PrintBluetoothThermal.connect(macPrinterAddress: address);
      _linkedAddress = ok ? address : null;
      link.value = ok ? PrinterLink.connected : PrinterLink.offline;
    } catch (_) {
      link.value = PrinterLink.offline;
    } finally {
      _connecting = false;
    }
  }

  Future<void> _sendQuiet(Future<void> Function() job) async {
    _sending = true;
    try {
      await job();
      if (link.value != PrinterLink.none) link.value = PrinterLink.connected;
    } catch (_) {
      if (link.value != PrinterLink.none) link.value = PrinterLink.offline;
    } finally {
      _sending = false;
    }
  }

  String _wrap(String input, int cols) {
    if (input.length <= cols) {
      return input;
    }
    return '${input.substring(0, cols - 1)}…';
  }
}

class PrintFailure implements Exception {
  PrintFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
