import 'dart:convert';
import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';

import '../core/app_state.dart';

class PrintException implements Exception {
  PrintException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Impression des étiquettes colis.
/// android : page du site convertie en PDF puis service d'impression Android (choix de l'imprimante) ;
/// network / bluetooth : imprimante d'étiquettes thermique en langage TSPL, sans aucun clic.
class LabelPrinter {
  LabelPrinter._();

  static Future<void> printLabels(List<int> ids) async {
    if (ids.isEmpty) return;
    final s = AppState.instance.settings;
    if (s.printMode == 'android') {
      await _android(ids);
    } else {
      await _direct(ids);
    }
  }

  static Future<void> _android(List<int> ids) async {
    final app = AppState.instance;
    final s = app.settings;
    final html = await app.api!.html('/labels', {'ids': ids.join(','), 'model': '${s.labelFormat}', 'copies': '${s.copies}', 'print': '0'});
    final square = html.contains('class="model-5"');
    final format = PdfPageFormat(100 * PdfPageFormat.mm, (square ? 100 : 150) * PdfPageFormat.mm, marginAll: 0);
    await Printing.layoutPdf(
      name: 'Etiquette ${ids.join('-')}',
      format: format,
      usePrinterSettings: false,
      onLayout: (f) => Printing.convertHtml(format: format, html: html, baseUrl: app.serverUrl),
    );
  }

  static Future<void> _direct(List<int> ids) async {
    final app = AppState.instance;
    final s = app.settings;
    if (!s.directReady) throw PrintException('Imprimante d’étiquettes non réglée : ouvrez Réglages › Impression.');
    final data = await app.api!.get('/labels/data', query: {'ids': ids.join(','), 'model': '${s.labelFormat}'});
    final square = data['format'] == '10x10';
    final sender = asMap(data['sender']);
    final bytes = <int>[];
    for (final label in asList(data['labels'])) {
      bytes.addAll(latin1.encode(Tspl.label(label, sender, square: square, copies: s.copies, dotsPerMm: s.dotsPerMm)));
    }
    await send(bytes);
  }

  static Future<void> send(List<int> bytes) async {
    final s = AppState.instance.settings;
    if (s.printMode == 'network') {
      Socket? socket;
      try {
        socket = await Socket.connect(s.host, s.port, timeout: const Duration(seconds: 6));
        socket.add(bytes);
        await socket.flush();
      } on SocketException {
        throw PrintException('Imprimante réseau injoignable (${s.host}:${s.port}).');
      } finally {
        await socket?.close();
      }
      return;
    }
    await ensureBluetooth();
    if (!await PrintBluetoothThermal.connectionStatus) {
      final ok = await PrintBluetoothThermal.connect(macPrinterAddress: s.btAddress);
      if (!ok) throw PrintException('Imprimante Bluetooth injoignable : allumez-la et vérifiez l’appairage.');
    }
    if (!await PrintBluetoothThermal.writeBytes(bytes)) {
      await PrintBluetoothThermal.disconnect;
      final ok = await PrintBluetoothThermal.connect(macPrinterAddress: s.btAddress);
      if (!ok || !await PrintBluetoothThermal.writeBytes(bytes)) throw PrintException('Envoi à l’imprimante Bluetooth échoué, réessayez.');
    }
  }

  static Future<void> ensureBluetooth() async {
    final statuses = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    if (statuses.values.any((st) => st.isPermanentlyDenied)) {
      throw PrintException('Autorisez le Bluetooth pour l’application dans les réglages d’Android.');
    }
    if (!await PrintBluetoothThermal.bluetoothEnabled) throw PrintException('Activez le Bluetooth de la tablette.');
  }

  static Future<List<BluetoothInfo>> pairedDevices() async {
    await ensureBluetooth();
    return PrintBluetoothThermal.pairedBluetooths;
  }
}

/// Étiquette 10 × 15 ou 10 × 10 en commandes TSPL (Xprinter, TSC, Gprinter, HPRT… en mode étiquette).
class Tspl {
  Tspl._();

  static String label(Map<String, dynamic> l, Map<String, dynamic> sender, {required bool square, int copies = 1, int dotsPerMm = 8}) {
    final k = dotsPerMm / 8;
    int d(num v) => (v * k).round();
    final b = StringBuffer()
      ..write('SIZE 100 mm,${square ? 100 : 150} mm\r\n')
      ..write('GAP 2 mm,0 mm\r\n')
      ..write('DIRECTION 1\r\n')
      ..write('REFERENCE 0,0\r\n')
      ..write('CLS\r\n');
    void text(num x, num y, String font, String value, {int scale = 1}) =>
        b.write('TEXT ${d(x)},${d(y)},"$font",0,$scale,$scale,"${ascii(value)}"\r\n');
    void bar(num y) => b.write('BAR ${d(16)},${d(y)},${d(768)},${d(3)}\r\n');
    final code = ascii((l['code'] ?? '').toString());
    final carrier = (l['carrier'] ?? '').toString();
    final store = (l['store'] ?? sender['name'] ?? '').toString();
    final sav = (l['sav'] ?? sender['phone'] ?? '').toString();

    b.write('BOX ${d(12)},${d(12)},${d(788)},${d(square ? 788 : 1188)},${d(3)}\r\n');
    text(30, 32, '3', cut(store.toUpperCase(), 22));
    if (carrier.isNotEmpty) text(430, 28, '4', cut(carrier.toUpperCase(), 14));
    if (!square) {
      bar(96);
      text(30, 110, '2', 'EXPEDITEUR');
      text(30, 136, '3', cut(store, 44));
      final from = [if (sav.isNotEmpty) 'Tel: $sav', if ((sender['address'] ?? '').toString().isNotEmpty) sender['address'].toString()].join(' - ');
      if (from.isNotEmpty) text(30, 168, '2', cut(from, 60));
      bar(204);
    } else {
      bar(80);
    }
    final top = square ? 92.0 : 216.0;
    text(30, top, '2', 'DESTINATAIRE');
    text(30, top + 26, '3', cut('Nom: ${l['name'] ?? ''}', 44));
    text(30, top + 58, '4', cut('Tel: ${l['phone'] ?? ''}', 30));
    final address = wrap('Adresse: ${l['address'] ?? ''}', 46, square ? 2 : 3);
    for (var i = 0; i < address.length; i++) {
      text(30, top + 100 + i * 28, '3', address[i]);
    }
    final cityY = top + 100 + address.length * 28 + 10;
    text(30, cityY, '5', cut((l['city'] ?? '').toString().toUpperCase(), 22));
    var y = cityY + 64;
    bar(y);
    if (!square) {
      final products = wrap('Produit: ${l['products'] ?? ''}', 64, 2);
      for (var i = 0; i < products.length; i++) {
        text(30, y + 12 + i * 24, '2', products[i]);
      }
      final flags = [l['open'] == true ? 'Ouverture autorisee' : 'Ne pas ouvrir', if (l['exchange'] == true) 'Echange', if ((l['note'] ?? '').toString().isNotEmpty) 'Note: ${l['note']}'].join(' - ');
      text(30, y + 12 + products.length * 24, '2', cut(flags, 64));
      y += 24 + (products.length + 1) * 24;
      bar(y);
    }
    text(30, y + 14, '5', cut('CRBT : ${l['amount'] ?? 0} DH', 20));
    final meta = [if ((l['weight'] ?? '').toString().isNotEmpty) 'POIDS ${l['weight']}', (l['date'] ?? '').toString()].where((e) => e.isNotEmpty).join('  ');
    text(500, y + 26, '2', cut(meta, 24));
    y += 74;
    bar(y);
    if (!square) {
      text(30, y + 10, '2', 'Merci de livrer le colis a la personne qui paie le CRBT');
      y += 40;
      bar(y);
    }
    b.write('BARCODE ${d(40)},${d(y + 18)},"128",${d(square ? 90 : 130)},1,0,${d(2)},${d(2)},"$code"\r\n');
    b.write('QRCODE ${d(square ? 600 : 590)},${d(y + 14)},L,${d(square ? 5 : 6)},A,0,"$code"\r\n');
    y += square ? 150 : 190;
    if (!square) {
      bar(y);
      text(30, y + 12, '2', cut('${store.toUpperCase()} vous remercie pour votre confiance.', 64));
      if (sav.isNotEmpty) text(30, y + 40, '2', cut('Service apres-vente : $sav', 64));
    } else if (sav.isNotEmpty) {
      text(30, y + 8, '2', cut('SAV : $sav', 60));
    }
    b.write('PRINT 1,${copies.clamp(1, 5)}\r\n');
    return b.toString();
  }

  static String cut(String value, int max) => value.length <= max ? value : '${value.substring(0, max - 1)}.';

  static List<String> wrap(String value, int width, int lines) {
    final words = ascii(value).split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final out = <String>[];
    var line = '';
    for (final w in words) {
      if ((line.isEmpty ? w.length : line.length + 1 + w.length) > width) {
        if (line.isNotEmpty) out.add(line);
        line = w.length > width ? w.substring(0, width) : w;
        if (out.length == lines) break;
      } else {
        line = line.isEmpty ? w : '$line $w';
      }
    }
    if (out.length < lines && line.isNotEmpty) out.add(line);
    if (out.length > lines) return out.sublist(0, lines);
    return out;
  }

  static const _map = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a', 'ç': 'c', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i', 'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o', 'û': 'u', 'ü': 'u', 'ú': 'u', 'ù': 'u',
    'ÿ': 'y', 'ñ': 'n', 'œ': 'oe', 'æ': 'ae', 'À': 'A', 'Â': 'A', 'Ä': 'A', 'Á': 'A', 'Ç': 'C', 'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
    'Î': 'I', 'Ï': 'I', 'Ô': 'O', 'Ö': 'O', 'Û': 'U', 'Ü': 'U', 'Ù': 'U', 'Œ': 'OE', 'Æ': 'AE', '’': "'", '‘': "'", '«': '"', '»': '"',
    '×': 'x', '·': '-', '–': '-', '—': '-', '…': '...', '"': "'",
  };

  /// Texte sans accents ni caractères hors ASCII (polices internes des imprimantes d'étiquettes).
  static String ascii(String value) {
    final out = StringBuffer();
    for (final ch in value.split('')) {
      final mapped = _map[ch];
      if (mapped != null) {
        out.write(mapped);
      } else if (ch.codeUnitAt(0) >= 32 && ch.codeUnitAt(0) < 127) {
        out.write(ch);
      }
    }
    return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
