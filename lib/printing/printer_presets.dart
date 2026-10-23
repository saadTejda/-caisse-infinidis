/// Modèles d'imprimantes ticket courants et leur réglage ESC/POS.
class PrinterPreset {
  const PrinterPreset({
    required this.id,
    required this.brand,
    required this.model,
    required this.paper,
    required this.columns,
    required this.connection,
    this.cut = true,
    this.drawer = false,
    this.accents = true,
    this.note = '',
  });

  final String id;
  final String brand;
  final String model;

  /// Largeur du papier en mm (58 ou 80).
  final int paper;

  /// Caractères par ligne (police normale).
  final int columns;

  /// 'bluetooth' ou 'network' (connexion la plus courante pour ce modèle).
  final String connection;
  final bool cut;
  final bool drawer;

  /// true : accents imprimés avec la page de codes CP1252 ; false : accents retirés (é → e).
  final bool accents;
  final String note;

  String get label => '$brand $model';
}

const printerPresets = <PrinterPreset>[
  PrinterPreset(id: 'epson_tm_t20', brand: 'Epson', model: 'TM-T20 II / III', paper: 80, columns: 48, connection: 'network', drawer: true, note: 'Version Ethernet (port 9100) ou Bluetooth selon le modèle.'),
  PrinterPreset(id: 'epson_tm_t82', brand: 'Epson', model: 'TM-T82 / T82X', paper: 80, columns: 48, connection: 'network', drawer: true),
  PrinterPreset(id: 'epson_tm_m30', brand: 'Epson', model: 'TM-m30 / m30II', paper: 80, columns: 48, connection: 'bluetooth', drawer: true),
  PrinterPreset(id: 'epson_tm_p20', brand: 'Epson', model: 'TM-P20 (mobile)', paper: 58, columns: 32, connection: 'bluetooth', cut: false),
  PrinterPreset(id: 'epson_tm_p80', brand: 'Epson', model: 'TM-P80 (mobile)', paper: 80, columns: 48, connection: 'bluetooth', cut: false),
  PrinterPreset(id: 'star_tsp143', brand: 'Star', model: 'TSP143 IIIBI', paper: 80, columns: 48, connection: 'bluetooth', drawer: true, note: 'Activez le mode d’émulation ESC/POS de l’imprimante (Star Line par défaut).'),
  PrinterPreset(id: 'star_mcprint3', brand: 'Star', model: 'mC-Print3', paper: 80, columns: 48, connection: 'bluetooth', drawer: true, note: 'Activez le mode d’émulation ESC/POS de l’imprimante.'),
  PrinterPreset(id: 'star_sml200', brand: 'Star', model: 'SM-L200 (mobile)', paper: 58, columns: 32, connection: 'bluetooth', cut: false, note: 'Mode d’émulation « ESC/POS mobile ».'),
  PrinterPreset(id: 'xprinter_58', brand: 'Xprinter', model: 'XP-58 / XP-58IIH', paper: 58, columns: 32, connection: 'bluetooth', cut: false, accents: false),
  PrinterPreset(id: 'xprinter_80', brand: 'Xprinter', model: 'XP-80 / XP-N160II', paper: 80, columns: 48, connection: 'network', drawer: true, accents: false),
  PrinterPreset(id: 'xprinter_p323b', brand: 'Xprinter', model: 'XP-P323B (mobile)', paper: 80, columns: 48, connection: 'bluetooth', cut: false, accents: false),
  PrinterPreset(id: 'goojprt_mtp2', brand: 'Goojprt', model: 'MTP-II / PT-210', paper: 58, columns: 32, connection: 'bluetooth', cut: false, accents: false),
  PrinterPreset(id: 'rongta_rpp02', brand: 'Rongta', model: 'RPP02 / RPP300', paper: 58, columns: 32, connection: 'bluetooth', cut: false, accents: false),
  PrinterPreset(id: 'hprt_mpt2', brand: 'HPRT', model: 'MPT-II / HM-E200', paper: 58, columns: 32, connection: 'bluetooth', cut: false, accents: false),
  PrinterPreset(id: 'bixolon_sppr200', brand: 'Bixolon', model: 'SPP-R200III', paper: 58, columns: 32, connection: 'bluetooth', cut: false),
  PrinterPreset(id: 'sunmi_inner', brand: 'Sunmi', model: 'V2 / T2 (imprimante intégrée)', paper: 58, columns: 32, connection: 'bluetooth', cut: false, drawer: false,
      note: 'Choisissez l’appareil Bluetooth « InnerPrinter » (imprimante interne).'),
  PrinterPreset(id: 'generic_58', brand: 'Générique', model: 'ESC/POS 58 mm', paper: 58, columns: 32, connection: 'bluetooth', cut: false, accents: false),
  PrinterPreset(id: 'generic_80', brand: 'Générique', model: 'ESC/POS 80 mm', paper: 80, columns: 48, connection: 'network', drawer: true, accents: false),
];

PrinterPreset presetById(String? id) => printerPresets.firstWhere((p) => p.id == id, orElse: () => printerPresets.last);

/// Réglage enregistré sur l'appareil (une imprimante par caisse).
class PrinterConfig {
  PrinterConfig({
    required this.presetId,
    required this.connection,
    this.address = '',
    this.deviceName = '',
    this.host = '',
    this.port = 9100,
    required this.paper,
    required this.columns,
    required this.cut,
    required this.drawer,
    required this.accents,
    this.copies = 1,
    this.autoPrint = true,
  });

  String presetId;
  String connection;
  String address;
  String deviceName;
  String host;
  int port;
  int paper;
  int columns;
  bool cut;
  bool drawer;
  bool accents;
  int copies;
  bool autoPrint;

  bool get ready => connection == 'network' ? host.isNotEmpty : address.isNotEmpty;

  String get summary {
    final where = connection == 'network' ? 'Réseau $host:$port' : 'Bluetooth ${deviceName.isNotEmpty ? deviceName : address}';
    return '${presetById(presetId).label} · $paper mm · $where';
  }

  factory PrinterConfig.fromPreset(PrinterPreset p) =>
      PrinterConfig(presetId: p.id, connection: p.connection, paper: p.paper, columns: p.columns, cut: p.cut, drawer: p.drawer, accents: p.accents);

  void applyPreset(PrinterPreset p) {
    presetId = p.id;
    connection = p.connection;
    paper = p.paper;
    columns = p.columns;
    cut = p.cut;
    drawer = p.drawer;
    accents = p.accents;
  }

  factory PrinterConfig.fromJson(Map<String, dynamic> j) => PrinterConfig(
        presetId: (j['preset'] ?? 'generic_80').toString(),
        connection: (j['connection'] ?? 'bluetooth').toString(),
        address: (j['address'] ?? '').toString(),
        deviceName: (j['device_name'] ?? '').toString(),
        host: (j['host'] ?? '').toString(),
        port: (j['port'] as num? ?? 9100).toInt(),
        paper: (j['paper'] as num? ?? 80).toInt(),
        columns: (j['columns'] as num? ?? 48).toInt(),
        cut: j['cut'] != false,
        drawer: j['drawer'] == true,
        accents: j['accents'] != false,
        copies: (j['copies'] as num? ?? 1).toInt().clamp(1, 3),
        autoPrint: j['auto_print'] != false,
      );

  Map<String, dynamic> toJson() => {
        'preset': presetId,
        'connection': connection,
        'address': address,
        'device_name': deviceName,
        'host': host,
        'port': port,
        'paper': paper,
        'columns': columns,
        'cut': cut,
        'drawer': drawer,
        'accents': accents,
        'copies': copies,
        'auto_print': autoPrint,
      };
}
