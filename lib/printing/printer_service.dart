import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
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
    if (config.accents) bytes.addAll([_esc, 0x74, config.codePage]);
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

  /// Code-barres CODE128 centré, avec le texte lisible dessous.
  void barcode(String data) {
    final value = _clean(data).codeUnits.where((c) => c >= 0x20 && c < 0x7F).toList();
    if (value.isEmpty || value.length > 40) return;
    if (!config.barcode) {
      text(String.fromCharCodes(value), alignTo: 'center', strong: true);
      return;
    }
    align('center');
    bytes.addAll([_gs, 0x68, 70]); // hauteur
    bytes.addAll([_gs, 0x77, value.length > 14 && config.paper < 80 ? 1 : 2]); // largeur du module (58 mm : 384 points)
    bytes.addAll([_gs, 0x48, 2]); // texte sous le code
    bytes.addAll([_gs, 0x6B, 73, value.length + 2, 0x7B, 0x42, ...value]);
    bytes.add(0x0A);
    align('left');
  }

  void feed(int lines) => bytes.addAll([_esc, 0x64, lines]);

  void cut() {
    switch (config.cutMode) {
      case 'full':
        bytes.addAll([_gs, 0x56, 0x00]);
      case 'partial':
        bytes.addAll([_gs, 0x56, 0x01]);
      case 'none':
        break;
      default:
        bytes.addAll([_gs, 0x56, 0x42, 0x00]);
    }
  }

  void drawer() => bytes.addAll([_esc, 0x70, config.drawerPin == 1 ? 0x01 : 0x00, 0x19, 0xFA]);

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

  /// Octets envoyés : Latin-1 tel quel pour WPC1252, table DOS pour PC850 / PC858 / PC437 (accent retiré s'il manque).
  List<int> _encode(String value) {
    final clean = _clean(value);
    if (!config.accents || config.codePage == 16) return clean.codeUnits.map((c) => c & 0xFF).toList();
    final table = config.codePage == 0 ? _cp437 : _cp850;
    final out = <int>[];
    for (final c in clean.codeUnits) {
      if (c < 0x80) {
        out.add(c);
      } else if (table.containsKey(c)) {
        out.add(table[c]!);
      } else if (c == 0x20AC && config.codePage == 19) {
        out.add(0xD5);
      } else {
        final plain = _stripAccents(String.fromCharCode(c)).codeUnits;
        out.add(plain.isNotEmpty && plain.first < 0x80 ? plain.first : 0x3F);
      }
    }
    return out;
  }

  static const _cp437 = <int, int>{
    0xC7: 0x80, 0xFC: 0x81, 0xE9: 0x82, 0xE2: 0x83, 0xE4: 0x84, 0xE0: 0x85, 0xE7: 0x87, 0xEA: 0x88, 0xEB: 0x89, 0xE8: 0x8A,
    0xEF: 0x8B, 0xEE: 0x8C, 0xC4: 0x8E, 0xC9: 0x90, 0xF4: 0x93, 0xF6: 0x94, 0xFB: 0x96, 0xF9: 0x97, 0xD6: 0x99, 0xDC: 0x9A,
    0xE1: 0xA0, 0xED: 0xA1, 0xF3: 0xA2, 0xFA: 0xA3, 0xF1: 0xA4, 0xD1: 0xA5, 0xB0: 0xF8,
  };

  static const _cp850 = <int, int>{
    0xC7: 0x80, 0xFC: 0x81, 0xE9: 0x82, 0xE2: 0x83, 0xE4: 0x84, 0xE0: 0x85, 0xE7: 0x87, 0xEA: 0x88, 0xEB: 0x89, 0xE8: 0x8A,
    0xEF: 0x8B, 0xEE: 0x8C, 0xC4: 0x8E, 0xC9: 0x90, 0xF4: 0x93, 0xF6: 0x94, 0xFB: 0x96, 0xF9: 0x97, 0xD6: 0x99, 0xDC: 0x9A,
    0xE1: 0xA0, 0xED: 0xA1, 0xF3: 0xA2, 0xFA: 0xA3, 0xF1: 0xA4, 0xD1: 0xA5, 0xC2: 0xB6, 0xC0: 0xB7, 0xCA: 0xD2, 0xCB: 0xD3,
    0xC8: 0xD4, 0xCE: 0xD7, 0xCF: 0xD8, 0xD4: 0xE2, 0xDB: 0xEA, 0xD9: 0xEB, 0xB0: 0xF8,
  };

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

/// État de la liaison avec l'imprimante, affiché dans la barre de la caisse.
enum PrinterLink { none, connecting, connected, offline }

class PrinterService with WidgetsBindingObserver {
  PrinterService._();

  static final instance = PrinterService._();

  static const _watchEvery = Duration(seconds: 15);

  PrinterConfig? config;

  /// none : pas d'imprimante ; connecting ; connected ; offline (éteinte, hors de portée, Bluetooth coupé).
  final ValueNotifier<PrinterLink> link = ValueNotifier(PrinterLink.none);

  Timer? _watch;
  String? _linkedAddress;
  bool _observing = false;
  bool _connecting = false;
  bool _sending = false;

  Future<PrinterConfig?> load() async {
    final raw = await AppState.instance.db.getValue('printer');
    config = raw is Map ? PrinterConfig.fromJson(Map<String, dynamic>.from(raw)) : null;
    return config;
  }

  Future<void> save(PrinterConfig value) async {
    config = value;
    await AppState.instance.db.setValue('printer', value.toJson());
    startWatch();
  }

  Future<void> remove() async {
    config = null;
    await AppState.instance.db.setValue('printer', null);
    _watch?.cancel();
    if (await PrintBluetoothThermal.connectionStatus) await PrintBluetoothThermal.disconnect;
    _linkedAddress = null;
    link.value = PrinterLink.none;
  }

  /// Garde l'imprimante Bluetooth connectée : essai au démarrage, puis toutes les 15 s et au retour dans l'application.
  void startWatch() {
    _watch?.cancel();
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    final c = config;
    if (c == null || !c.ready) {
      link.value = PrinterLink.none;
      return;
    }
    if (c.connection == 'network') {
      link.value = PrinterLink.connected;
      return;
    }
    if (!c.keepAlive) {
      link.value = PrinterLink.offline;
      return;
    }
    _watch = Timer.periodic(_watchEvery, (_) => check());
    check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }

  /// Vérifie la liaison et reconnecte sans rien demander à l'utilisateur.
  Future<void> check() async {
    final c = config;
    if (c == null || !c.ready || c.connection != 'bluetooth' || _connecting || _sending) return;
    try {
      if (!await _bluetoothUsable()) {
        link.value = PrinterLink.offline;
        return;
      }
      if (await _linkedTo(c.address)) {
        link.value = PrinterLink.connected;
        return;
      }
      if (c.keepAlive) await connectNow(quiet: true);
    } catch (_) {
      link.value = PrinterLink.offline;
    }
  }

  /// Connexion à l'imprimante réglée. quiet : sans demande d'autorisation (vérification de fond).
  Future<bool> connectNow({bool quiet = false}) async {
    final c = config;
    if (c == null || !c.ready || c.connection != 'bluetooth' || _connecting) return false;
    _connecting = true;
    link.value = PrinterLink.connecting;
    try {
      if (quiet) {
        if (!await _bluetoothUsable()) {
          link.value = PrinterLink.offline;
          return false;
        }
      } else {
        await ensureBluetooth();
      }
      if (await _linkedTo(c.address)) {
        link.value = PrinterLink.connected;
        return true;
      }
      final ok = await _connect(c.address);
      link.value = ok ? PrinterLink.connected : PrinterLink.offline;
      return ok;
    } catch (_) {
      link.value = PrinterLink.offline;
      if (!quiet) rethrow;
      return false;
    } finally {
      _connecting = false;
    }
  }

  /// true si la liaison ouverte est bien celle de cette imprimante (sinon elle est fermée).
  Future<bool> _linkedTo(String address) async {
    if (!await PrintBluetoothThermal.connectionStatus) return false;
    if (_linkedAddress == address) return true;
    await PrintBluetoothThermal.disconnect;
    _linkedAddress = null;
    return false;
  }

  Future<bool> _connect(String address) async {
    final ok = await PrintBluetoothThermal.connect(macPrinterAddress: address);
    _linkedAddress = ok ? address : null;
    return ok;
  }

  Future<bool> _bluetoothUsable() async {
    if (!await Permission.bluetoothConnect.isGranted) return false;
    return PrintBluetoothThermal.bluetoothEnabled;
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
    while (_connecting) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    _sending = true;
    try {
      for (var attempt = 1; attempt <= 2; attempt++) {
        if (!await _linkedTo(c.address)) {
          link.value = PrinterLink.connecting;
          final connected = await _connect(c.address);
          if (!connected) {
            link.value = PrinterLink.offline;
            if (attempt == 1) {
              await Future<void>.delayed(const Duration(milliseconds: 900));
              continue;
            }
            throw PrintException('Imprimante injoignable : allumez-la, rapprochez-la de la tablette et vérifiez l’appairage Bluetooth.');
          }
          link.value = PrinterLink.connected;
        }
        if (await PrintBluetoothThermal.writeBytes(bytes)) {
          link.value = PrinterLink.connected;
          return;
        }
        await PrintBluetoothThermal.disconnect;
        _linkedAddress = null;
        link.value = PrinterLink.offline;
      }
      throw PrintException('Envoi à l’imprimante échoué après reconnexion, réessayez.');
    } finally {
      _sending = false;
    }
  }

  /// Ticket test : chaque partie correspond à une question de l'assistant (accents, largeur, code-barres, coupe).
  Future<void> printTest(PrinterConfig c) async {
    final t = TicketBuilder(c)..init();
    t.text('INFINIDIS', alignTo: 'center', strong: true, big: true);
    t.text('Ticket test', alignTo: 'center');
    t.hr();
    t.wrap(presetById(c.presetId).label);
    t.pair('Papier', '${c.paper} mm');
    t.pair('Caractères / ligne', '${c.columns}');
    t.pair('Accents', c.accents ? (codePages[c.codePage] ?? '${c.codePage}') : 'retirés');
    t.hr();
    t.text('1. Accents : é è ê à â ç ô û É À Ç');
    t.text('2. Ligne pleine (doit tenir sur 1 ligne) :');
    t.text(List.generate(c.columns, (i) => '${(i + 1) % 10}').join());
    t.text('3. Code-barres :');
    t.barcode('TEST-123456');
    t.pair('4. Total', '123,45', strong: true);
    t.hr();
    t.text('Répondez aux questions', alignTo: 'center');
    t.text('sur la tablette.', alignTo: 'center');
    t.feed(3);
    if (c.cut) t.cut();
    await send(c, t.bytes);
  }

  Future<void> testDrawer(PrinterConfig c) async {
    final t = TicketBuilder(c)..init();
    t.drawer();
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
      if (toNum(ticket['shipping']) > 0) t.pair('Expédition', ticket['shipping'].toString());
      if (ticket['vat'] == true && toNum(ticket['total_tax']) > 0) t.pair('dont TVA', ticket['total_tax'].toString());
      t.pair('TOTAL $currency', ticket['total'].toString(), strong: true);
      for (final raw in (ticket['payments'] as List? ?? [])) {
        final p = Map<String, dynamic>.from(raw as Map);
        t.pair(p['method'].toString(), p['amount'].toString());
      }
      if (toNum(ticket['change']) > 0) t.pair('Rendu', ticket['change'].toString());
      if (toNum(ticket['due']) > 0) t.pair('Reste dû (crédit)', ticket['due'].toString(), strong: true);
      final shipment = ticket['shipment'];
      if (shipment is Map) {
        t.hr();
        t.text('A LIVRER - colis ${shipment['code']}', strong: true);
        t.wrap('${shipment['name']} · ${shipment['phone']}');
        t.wrap('${shipment['address']}${(shipment['city'] ?? '').toString().isNotEmpty ? ', ${shipment['city']}' : ''}');
        t.pair('A encaisser à la livraison', '${ticket['cod'] ?? '0.00'} $currency', strong: true);
      }
      t.hr();
      final footer = (company['footer'] ?? '').toString().trim();
      t.text(footer.isNotEmpty ? footer : 'Merci de votre visite', alignTo: 'center');
      if (ticket['offline'] != true) t.barcode(ticket['number'].toString());
      t.feed(3);
      if (c.cut) t.cut();
    }
    await send(c, t.bytes);
  }

  /// Bon de mouvement de caisse (dépense, entrée ou sortie d'argent), avec signature.
  Future<void> printMovement({required String label, required String amount, required String reason, required String date, bool openDrawer = false}) async {
    final c = config;
    if (c == null || !c.ready) throw PrintException('Aucune imprimante réglée : ouvrez « Imprimante » dans le menu.');
    final app = AppState.instance;
    final t = TicketBuilder(c)..init();
    if (openDrawer && c.drawer) t.drawer();
    t.text((app.company['name'] ?? 'INFINIDIS').toString(), alignTo: 'center', strong: true);
    t.text(label.toUpperCase(), alignTo: 'center', strong: true, big: c.paper >= 80);
    t.hr();
    t.pair('Date', date);
    if ((app.store?['name'] ?? '').toString().isNotEmpty) t.text('Magasin : ${app.store!['name']}');
    t.text('Caissier : ${app.user?['name'] ?? ''}');
    t.wrap('Motif : $reason');
    t.hr();
    t.pair('MONTANT ${app.currency}', amount, strong: true);
    t.feed(2);
    t.text('Signature :');
    t.feed(3);
    if (c.cut) t.cut();
    await send(c, t.bytes);
  }

  /// Ticket de retour (et bon d'avoir s'il y en a un).
  Future<void> printReturn(Map<String, dynamic> doc, {bool openDrawer = false}) async {
    final c = config;
    if (c == null || !c.ready) throw PrintException('Aucune imprimante réglée : ouvrez « Imprimante » dans le menu.');
    final app = AppState.instance;
    final company = app.company;
    final currency = app.currency;
    final t = TicketBuilder(c)..init();
    if (openDrawer && c.drawer) t.drawer();
    t.text((company['name'] ?? 'INFINIDIS').toString(), alignTo: 'center', strong: true, big: c.paper >= 80);
    t.text('RETOUR ${doc['number']}', alignTo: 'center', strong: true);
    t.hr();
    t.pair('Ticket d’origine', doc['sale_number'].toString());
    t.pair('Date', (doc['date'] ?? '').toString());
    if ((doc['store'] ?? '').toString().isNotEmpty) t.text('Magasin : ${doc['store']}');
    if ((doc['user'] ?? '').toString().isNotEmpty) t.text('Caissier : ${doc['user']}');
    if (doc['contact'] is Map) t.text('Client : ${(doc['contact'] as Map)['name']}');
    t.wrap('Motif : ${doc['reason']}');
    t.hr();
    for (final raw in (doc['lines'] as List? ?? [])) {
      final l = Map<String, dynamic>.from(raw as Map);
      t.wrap(l['label'].toString());
      t.pair('  ${l['quantity']} x · ${l['condition']}', l['total'].toString());
    }
    t.hr();
    t.pair('TOTAL RETOUR $currency', doc['total'].toString(), strong: true);
    if (toNum(doc['debt']) > 0) t.pair('Déduit du dû client', doc['debt'].toString());
    if (toNum(doc['refund']) > 0) t.pair('Remboursé (${doc['refund_label']})', doc['refund'].toString(), strong: true);
    final voucher = doc['voucher'];
    if (voucher is Map) {
      t.hr();
      t.text('BON D’AVOIR', alignTo: 'center', strong: true, big: c.paper >= 80);
      t.text('${doc['refund']} $currency', alignTo: 'center', strong: true);
      if ((voucher['expires_on'] ?? '').toString().isNotEmpty) t.text('Valable jusqu’au ${voucher['expires_on']}', alignTo: 'center');
      t.barcode(voucher['code'].toString());
    } else {
      t.barcode(doc['number'].toString());
    }
    t.feed(3);
    if (c.cut) t.cut();
    await send(c, t.bytes);
  }
}
