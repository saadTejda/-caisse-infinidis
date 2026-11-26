import 'package:cafe_resto_caisse/printing/ticket_printer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('le nom Bluetooth le plus précis gagne', () {
    expect(detectPreset('XP-58IIH')?.id, 'xprinter_58');
    expect(detectPreset('Star TSP100IV')?.id, 'star_tsp100');
    expect(detectPreset('InnerPrinter')?.id, 'sunmi_inner');
    expect(detectPreset('imprimante inconnue'), isNull);
  });

  test('la config survit au JSON et part des réglages serveur', () {
    final printer = TicketPrinter.fromServer({
      'pos.receipt_printer_enabled': true,
      'pos.receipt_printer_transport': 'wifi',
      'pos.receipt_printer_host': '192.168.1.40',
      'pos.receipt_printer_port': 9100,
      'pos.receipt_printer_paper_width': '58',
    }, 'receipt');
    final restored = TicketPrinter.fromJson(printer.toJson());
    expect(restored.role, 'receipt');
    expect(restored.enabled, isTrue);
    expect(restored.connection, 'network');
    expect(restored.host, '192.168.1.40');
    expect(restored.paper, 58);
    expect(restored.presetId, 'generic_58');
  });
}
