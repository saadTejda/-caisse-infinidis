import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import 'printer_presets.dart';

class PrintException implements Exception {
  PrintException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Construit un ticket en commandes ESC/POS brutes (compatibles avec la plupart des imprimantes ticket).
class TicketBuilder {
  TicketBuilder(this.config);

  final PrinterConfig config;
  final List<int> bytes = [];

  static const _esc = 0x1B;
  static const _gs = 0x1D;

  int get cols => config.columns;

  void init() {
    bytes.addAll([_esc, 0x40]);
    if (config.accents) bytes.addAll([_esc, 0x74, 16]); // page de codes WPC1252
  }

  void align(String a) => bytes.addAll([_esc, 0x61, a == 'center' ? 1 : (a == 'right' ? 2 : 0)]);

  void bold(bool on) => bytes.addAll([_esc, 0x45, on ? 1 : 0]);

  void size(bool big) => bytes.addAll([_gs, 0x21, big ? 0x11 : 0x00]);

  void text(String value, {String alignTo = 'left', bool strong = false, bool big = false}) {
    align(alignTo);
    if (strong) bold(true);
    if (big) size(true);
    bytes.addAll(_encode(value));
    bytes.add(0x0A);
    if (big) size(false);
    if (strong) bold(false);
    if (alignTo != 'left') align('left');
  }

  /// Texte à gauche, montant à droite sur la même ligne.
  void pair(String left, String right, {bool strong = false}) {
    final width = cols;
    final r = _clean(right);
    var l = _clean(left);
    final room = width - r.length - 1;
    if (room < 4) {
      text(l, strong: strong);
      text(r, alignTo: 'right', strong: strong);
      return;
    }
    if (l.length > room) l = l.substring(0, room);
    text(l.padRight(width - r.length) + r, strong: strong);
  }

  void wrap(String value, {bool strong = false}) {
    final words = _clean(value).split(RegExp(r'\s+'));
    var line = '';
    for (final w in words) {
      if (line.isEmpty) {
        line = w;
      } else if (line.length + 1 + w.length <= cols) {
        line = '$line $w';
      } else {
        text(line, strong: strong);
        line = w;
      }
      while (line.length > cols) {
        text(line.substring(0, cols), strong: strong);
        line = line.substring(cols);
      }
    }
    if (line.isNotEmpty) text(line, strong: strong);
  }

  void hr() => text('-' * cols);

  void feed(int lines) => bytes.addAll([_esc, 0x64, lines]);

  void cut() => bytes.addAll([_gs, 0x56, 0x42, 0x00]);

  void drawer() => bytes.addAll([_esc, 0x70, 0x00, 0x19, 0xFA]);

  String _clean(String value) {
    var s = value
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('…', '...')
        .replaceAll('·', '-')
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u202F', ' ')
        .replaceAll('€', 'EUR');
    if (!config.accents) s = _stripAccents(s);
    return String.fromCharCodes(s.runes.map((c) => c <= 0xFF ? c : 0x3F));
  }

  List<int> _encode(String value) => _clean(value).codeUnits.map((c) => c & 0xFF).toList();

  static String _stripAccents(String s) {
    const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝ';
    const to = 'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUY';
    final out = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      out.write(i >= 0 ? to[i] : ch);
    }
    return out.toString().replaceAll('œ', 'oe').replaceAll('Œ', 'OE').replaceAll('æ', 'ae').replaceAll('°', 'o');
  }
}

class PrinterService {
  PrinterService._();

  static final instance = PrinterService._();

  PrinterConfig? config;

  Future<PrinterConfig?> load() async {
    final raw = await AppState.instance.db.getValue('printer');
    config = raw is Map ? PrinterConfig.fromJson(Map<String, dynamic>.from(raw)) : null;
    return config;
  }

  Future<void> save(PrinterConfig value) async {
    config = value;
    await AppState.instance.db.setValue('printer', value.toJson());
  }

  Future<void> remove() async {
    config = null;
    await AppState.instance.db.setValue('printer', null);
  }

  /// Autorisations Bluetooth (Android 12 et plus).
  Future<void> ensureBluetooth() async {
    final statuses = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    if (statuses.values.any((s) => s.isPermanentlyDenied)) {
      throw PrintException('Autorisez le Bluetooth pour l’application dans les réglages d’Android.');
    }
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw PrintException('Activez le Bluetooth de la tablette.');
    }
  }

  Future<List<BluetoothInfo>> pairedDevices() async {
    await ensureBluetooth();
    return PrintBluetoothThermal.pairedBluetooths;
  }

  Future<void> send(PrinterConfig c, List<int> bytes) async {
    if (!c.ready) throw PrintException('Imprimante non réglée.');
    if (c.connection == 'network') {
      Socket? socket;
      try {
        socket = await Socket.connect(c.host, c.port, timeout: const Duration(seconds: 6));
        socket.add(bytes);
        await socket.flush();
      } on SocketException {
        throw PrintException('Imprimante réseau injoignable (${c.host}:${c.port}).');
      } finally {
        await socket?.close();
      }
      return;
    }
    await ensureBluetooth();
    if (!await PrintBluetoothThermal.connectionStatus) {
      final ok = await PrintBluetoothThermal.connect(macPrinterAddress: c.address);
      if (!ok) throw PrintException('Connexion Bluetooth impossible : allumez l’imprimante et vérifiez l’appairage.');
    }
    final ok = await PrintBluetoothThermal.writeBytes(bytes);
    if (!ok) {
      await PrintBluetoothThermal.disconnect;
      throw PrintException('Envoi à l’imprimante échoué, réessayez.');
    }
  }

  Future<void> printTest(PrinterConfig c) async {
    final t = TicketBuilder(c)..init();
    t.text('INFINIDIS', alignTo: 'center', strong: true, big: true);
    t.text('Impression test', alignTo: 'center');
    t.hr();
    t.text(presetById(c.presetId).label);
    t.pair('Papier', '${c.paper} mm');
    t.pair('Colonnes', '${c.columns}');
    t.text('Accents : é è à ç ô');
    t.text('1234567890' * (c.columns ~/ 10));
    t.hr();
    t.text('Si ce ticket est lisible,', alignTo: 'center');
    t.text('le réglage est bon.', alignTo: 'center');
    t.feed(3);
    if (c.cut) t.cut();
    await send(c, t.bytes);
  }

  Future<void> openDrawer() async {
    final c = config;
    if (c == null || !c.drawer) return;
    final t = TicketBuilder(c)..init();
    t.drawer();
    await send(c, t.bytes);
  }

  /// Ticket de caisse (vente en ligne ou hors ligne).
  Future<void> printTicket(Map<String, dynamic> ticket, {bool openDrawer = false}) async {
    final c = config;
    if (c == null || !c.ready) throw PrintException('Aucune imprimante réglée : ouvrez « Imprimante » dans le menu.');
    final app = AppState.instance;
    final company = app.company;
    final currency = app.currency;
    final t = TicketBuilder(c)..init();
    if (openDrawer && c.drawer) t.drawer();
    for (var copy = 0; copy < c.copies; copy++) {
      t.text((company['name'] ?? 'INFINIDIS').toString(), alignTo: 'center', strong: true, big: c.paper >= 80);
      for (final line in [company['address'], company['phone']]) {
        if ((line ?? '').toString().trim().isNotEmpty) t.text(line.toString(), alignTo: 'center');
      }
      final ids = [
        if ((company['ice'] ?? '').toString().isNotEmpty) 'ICE ${company['ice']}',
        if ((company['if'] ?? '').toString().isNotEmpty) 'IF ${company['if']}',
        if ((company['rc'] ?? '').toString().isNotEmpty) 'RC ${company['rc']}',
      ];
      if (ids.isNotEmpty) t.text(ids.join(' - '), alignTo: 'center');
      t.hr();
      t.pair('Ticket ${ticket['number']}', (ticket['date'] ?? '').toString(), strong: true);
      if ((ticket['store'] ?? '').toString().isNotEmpty) t.text('Magasin : ${ticket['store']}');
      if ((ticket['cashier'] ?? '').toString().isNotEmpty) t.text('Caissier : ${ticket['cashier']}');
      if ((ticket['contact'] ?? '').toString().isNotEmpty) t.text('Client : ${ticket['contact']}');
      if (ticket['offline'] == true) t.text('Vente hors ligne (numéro provisoire)');
      t.hr();
      for (final raw in (ticket['lines'] as List? ?? [])) {
        final l = Map<String, dynamic>.from(raw as Map);
        t.wrap(l['label'].toString());
        t.pair('  ${l['quantity']} x ${l['unit_price']}', l['total'].toString());
      }
      t.hr();
      if (toNum(ticket['discount']) > 0) t.pair('Remise', '-${ticket['discount']}');
      if (ticket['vat'] == true && toNum(ticket['total_tax']) > 0) t.pair('dont TVA', ticket['total_tax'].toString());
      t.pair('TOTAL $currency', ticket['total'].toString(), strong: true);
      for (final raw in (ticket['payments'] as List? ?? [])) {
        final p = Map<String, dynamic>.from(raw as Map);
        t.pair(p['method'].toString(), p['amount'].toString());
      }
      if (toNum(ticket['change']) > 0) t.pair('Rendu', ticket['change'].toString());
      if (toNum(ticket['due']) > 0) t.pair('Reste dû (crédit)', ticket['due'].toString(), strong: true);
      t.hr();
      final footer = (company['footer'] ?? '').toString().trim();
      t.text(footer.isNotEmpty ? footer : 'Merci de votre visite', alignTo: 'center');
      t.feed(3);
      if (c.cut) t.cut();
    }
    await send(c, t.bytes);
  }
}
