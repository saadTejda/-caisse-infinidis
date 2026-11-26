import 'ticket_printer.dart';

/// Ticket ESC/POS. Les étiquettes TSPL ne passent pas par ici.
class TicketBuilder {
  TicketBuilder(this.config);

  final TicketPrinter config;
  final List<int> bytes = [];

  static const _esc = 0x1B;
  static const _gs = 0x1D;

  int get cols => config.columns;

  void init() {
    bytes.addAll([_esc, 0x40]);
    if (config.accents) bytes.addAll([_esc, 0x74, config.codePage]);
  }

  void align(String value) => bytes.addAll([_esc, 0x61, value == 'center' ? 1 : (value == 'right' ? 2 : 0)]);

  void bold(bool on) => bytes.addAll([_esc, 0x45, on ? 1 : 0]);

  void size(bool big) => bytes.addAll([_gs, 0x21, big ? 0x11 : 0x00]);

  void text(String value, {String alignTo = 'left', bool strong = false}) {
    align(alignTo);
    if (strong) bold(true);
    bytes.addAll(_encode(value));
    bytes.add(0x0A);
    if (strong) bold(false);
    if (alignTo != 'left') align('left');
  }

  void pair(String left, String right, {bool strong = false}) {
    final r = _clean(right);
    var l = _clean(left);
    final room = cols - r.length - 1;
    if (room < 4) {
      text(l, strong: strong);
      text(r, alignTo: 'right', strong: strong);
      return;
    }
    if (l.length > room) l = l.substring(0, room);
    text(l.padRight(cols - r.length) + r, strong: strong);
  }

  void wrap(String value) {
    final words = _clean(value).split(RegExp(r'\s+'));
    var line = '';
    for (final word in words) {
      if (line.isEmpty) {
        line = word;
      } else if (line.length + 1 + word.length <= cols) {
        line = '$line $word';
      } else {
        text(line);
        line = word;
      }
      while (line.length > cols) {
        text(line.substring(0, cols));
        line = line.substring(cols);
      }
    }
    if (line.isNotEmpty) text(line);
  }

  void hr() => text('-' * cols);

  void barcode(String data) {
    final value = _clean(data).codeUnits.where((c) => c >= 0x20 && c < 0x7F).toList();
    if (value.isEmpty || value.length > 40) return;
    if (!config.barcode) {
      text(String.fromCharCodes(value), alignTo: 'center', strong: true);
      return;
    }
    align('center');
    bytes.addAll([_gs, 0x68, 70]);
    bytes.addAll([_gs, 0x77, value.length > 14 && config.paper < 80 ? 1 : 2]);
    bytes.addAll([_gs, 0x48, 2]);
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

  String _clean(String value) {
    var text = value
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('…', '...')
        .replaceAll('·', '-');
    if (!config.accents) text = _stripAccents(text);
    return String.fromCharCodes(text.runes.map((c) => c <= 0xFF ? c : 0x3F));
  }

  List<int> _encode(String value) {
    final clean = _clean(value);
    if (!config.accents || config.codePage == 16) {
      return clean.codeUnits.map((c) => c & 0xFF).toList();
    }
    final table = config.codePage == 0 ? _cp437 : _cp850;
    final out = <int>[];
    for (final c in clean.codeUnits) {
      if (c < 0x80) {
        out.add(c);
      } else if (table.containsKey(c)) {
        out.add(table[c]!);
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
    0xE1: 0xA0, 0xED: 0xA1, 0xF3: 0xA2, 0xFA: 0xA3, 0xF1: 0xA4, 0xD1: 0xA5,
  };

  static const _cp850 = <int, int>{
    0xC7: 0x80, 0xFC: 0x81, 0xE9: 0x82, 0xE2: 0x83, 0xE4: 0x84, 0xE0: 0x85, 0xE7: 0x87, 0xEA: 0x88, 0xEB: 0x89, 0xE8: 0x8A,
    0xEF: 0x8B, 0xEE: 0x8C, 0xC4: 0x8E, 0xC9: 0x90, 0xF4: 0x93, 0xF6: 0x94, 0xFB: 0x96, 0xF9: 0x97, 0xD6: 0x99, 0xDC: 0x9A,
    0xE1: 0xA0, 0xED: 0xA1, 0xF3: 0xA2, 0xFA: 0xA3, 0xF1: 0xA4, 0xD1: 0xA5, 0xC8: 0xD4, 0xCA: 0xD2, 0xC0: 0xB7,
  };

  static String _stripAccents(String value) {
    const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝ';
    const to = 'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUY';
    final out = StringBuffer();
    for (final char in value.split('')) {
      final index = from.indexOf(char);
      out.write(index >= 0 ? to[index] : char);
    }
    return out.toString();
  }
}
