/// Imprimantes ticket ESC/POS courantes : un profil complet par modèle (papier, colonnes, coupe, tiroir,
/// page des accents, code-barres) et les mots du nom Bluetooth qui permettent de le reconnaître.
/// Les valeurs sont les réglages ESC/POS standard ; le ticket test et l'assistant les ajustent sur place.
class PrinterPreset {
  const PrinterPreset({
    required this.id,
    required this.brand,
    required this.model,
    required this.paper,
    this.columns = 0,
    this.connection = 'bluetooth',
    this.cut = true,
    this.cutMode = 'feed',
    this.drawer = false,
    this.drawerPin = 0,
    this.accents = true,
    this.codePage = 16,
    this.barcode = true,
    this.match = const [],
    this.note = '',
  });

  final String id;
  final String brand;
  final String model;

  /// Largeur du papier en mm (58 ou 80).
  final int paper;

  /// Caractères par ligne en police normale (0 = 32 en 58 mm, 48 en 80 mm).
  final int columns;

  /// 'bluetooth' ou 'network'.
  final String connection;
  final bool cut;

  /// Commande de coupe : voir [cutModes].
  final String cutMode;
  final bool drawer;

  /// Broche du tiroir-caisse (0 = broche 2, 1 = broche 5).
  final int drawerPin;

  /// true : accents imprimés avec la page [codePage] ; false : accents retirés (é → e).
  final bool accents;

  /// Numéro de page de caractères ESC t (voir [codePages]).
  final int codePage;

  /// Code-barres CODE128 imprimé (sinon le numéro en texte).
  final bool barcode;

  /// Morceaux du nom Bluetooth (en minuscules) qui désignent ce modèle.
  final List<String> match;
  final String note;

  int get cols => columns > 0 ? columns : (paper >= 80 ? 48 : 32);

  String get label => brand == 'Autre' ? model : '$brand $model';
}

/// Commandes de coupe du papier.
const cutModes = <String, String>{
  'feed': 'Avance puis coupe (GS V 66)',
  'full': 'Coupe totale (GS V 0)',
  'partial': 'Coupe partielle (GS V 1)',
  'none': 'Pas de coupe',
};

/// Pages de caractères ESC t (numérotation Epson, reprise par la plupart des imprimantes ESC/POS).
const codePages = <int, String>{
  16: 'WPC1252 · Europe de l’Ouest',
  2: 'PC850 · Multilingue',
  19: 'PC858 · Multilingue + €',
  0: 'PC437 · USA',
};

const _desk = 'Imprimante de comptoir : coupe et tiroir-caisse.';
const _mobile = 'Imprimante portable : sans coupe automatique (déchirez le ticket).';
const _star = 'Réglez l’imprimante en émulation « ESC/POS » (outil Star Quick Setup), sinon le ticket est illisible.';

const printerPresets = <PrinterPreset>[
  // Epson (ESC/POS d'origine)
  PrinterPreset(id: 'epson_tm_m30', brand: 'Epson', model: 'TM-m30 / m30II / m30III', paper: 80, drawer: true, match: ['tm-m30'], note: _desk),
  PrinterPreset(id: 'epson_tm_m10', brand: 'Epson', model: 'TM-m10', paper: 58, drawer: true, match: ['tm-m10'], note: _desk),
  PrinterPreset(id: 'epson_tm_t20', brand: 'Epson', model: 'TM-T20II / III / IV', paper: 80, drawer: true, match: ['tm-t20'], note: _desk),
  PrinterPreset(id: 'epson_tm_t82', brand: 'Epson', model: 'TM-T82 / T82X / T82III', paper: 80, drawer: true, match: ['tm-t82'], note: _desk),
  PrinterPreset(id: 'epson_tm_t88', brand: 'Epson', model: 'TM-T88V / VI / VII', paper: 80, drawer: true, match: ['tm-t88'], note: _desk),
  PrinterPreset(id: 'epson_tm_p20', brand: 'Epson', model: 'TM-P20 / P20II', paper: 58, cut: false, cutMode: 'none', match: ['tm-p20'], note: _mobile),
  PrinterPreset(id: 'epson_tm_p60', brand: 'Epson', model: 'TM-P60II', paper: 58, cut: false, cutMode: 'none', match: ['tm-p60'], note: _mobile),
  PrinterPreset(id: 'epson_tm_p80', brand: 'Epson', model: 'TM-P80 / P80II', paper: 80, cut: false, cutMode: 'none', match: ['tm-p80'], note: _mobile),

  // Star (en émulation ESC/POS)
  PrinterPreset(id: 'star_tsp100', brand: 'Star', model: 'TSP143IIIBI / TSP100IV', paper: 80, drawer: true, match: ['tsp143', 'tsp100', 'tsp1'], note: _star),
  PrinterPreset(id: 'star_tsp654', brand: 'Star', model: 'TSP654II BT', paper: 80, drawer: true, match: ['tsp654', 'tsp6'], note: _star),
  PrinterPreset(id: 'star_mcprint3', brand: 'Star', model: 'mC-Print3', paper: 80, drawer: true, match: ['mc-print3', 'mcprint3', 'mcp3'], note: _star),
  PrinterPreset(id: 'star_mcprint2', brand: 'Star', model: 'mC-Print2', paper: 58, drawer: true, match: ['mc-print2', 'mcprint2', 'mcp2'], note: _star),
  PrinterPreset(id: 'star_sml200', brand: 'Star', model: 'SM-L200', paper: 58, cut: false, cutMode: 'none', match: ['sm-l200'], note: _star),
  PrinterPreset(id: 'star_sms230', brand: 'Star', model: 'SM-S230i', paper: 58, cut: false, cutMode: 'none', match: ['sm-s230', 'sm-s2'], note: _star),

  // Bixolon
  PrinterPreset(id: 'bixolon_r200', brand: 'Bixolon', model: 'SPP-R200III', paper: 58, cut: false, cutMode: 'none', match: ['spp-r200', 'r200'], note: _mobile),
  PrinterPreset(id: 'bixolon_r300', brand: 'Bixolon', model: 'SPP-R300', paper: 80, cut: false, cutMode: 'none', match: ['spp-r300'], note: _mobile),
  PrinterPreset(id: 'bixolon_r310', brand: 'Bixolon', model: 'SPP-R310', paper: 80, cut: false, cutMode: 'none', match: ['spp-r310'], note: _mobile),
  PrinterPreset(id: 'bixolon_srp350', brand: 'Bixolon', model: 'SRP-350plusIII / SRP-350III', paper: 80, drawer: true, match: ['srp-350', 'srp-'], note: _desk),

  // Citizen
  PrinterPreset(id: 'citizen_cmp20', brand: 'Citizen', model: 'CMP-20II', paper: 58, cut: false, cutMode: 'none', match: ['cmp-20'], note: _mobile),
  PrinterPreset(id: 'citizen_cmp30', brand: 'Citizen', model: 'CMP-30II', paper: 80, cut: false, cutMode: 'none', match: ['cmp-30'], note: _mobile),
  PrinterPreset(id: 'citizen_cts310', brand: 'Citizen', model: 'CT-S310II', paper: 80, drawer: true, match: ['ct-s310'], note: _desk),

  // Sewoo
  PrinterPreset(id: 'sewoo_lkp20', brand: 'Sewoo', model: 'LK-P20 / LK-P21', paper: 58, cut: false, cutMode: 'none', match: ['lk-p2'], note: _mobile),
  PrinterPreset(id: 'sewoo_lkp30', brand: 'Sewoo', model: 'LK-P30 / LK-P31', paper: 80, cut: false, cutMode: 'none', match: ['lk-p3'], note: _mobile),

  // Xprinter
  PrinterPreset(id: 'xprinter_58', brand: 'Xprinter', model: 'XP-58IIH / XP-58IIB / XP-P200', paper: 58, cut: false, cutMode: 'none', accents: false, match: ['xp-58', 'xp-p2'], note: _mobile),
  PrinterPreset(id: 'xprinter_p300', brand: 'Xprinter', model: 'XP-P300 / XP-P323B', paper: 80, cut: false, cutMode: 'none', accents: false, match: ['xp-p3'], note: _mobile),
  PrinterPreset(id: 'xprinter_p810', brand: 'Xprinter', model: 'XP-P810', paper: 80, cut: false, cutMode: 'none', accents: false, match: ['xp-p8'], note: _mobile),
  PrinterPreset(id: 'xprinter_80', brand: 'Xprinter', model: 'XP-Q800 / XP-N160II / XP-Q200 (Bluetooth)', paper: 80, drawer: true, accents: false, match: ['xp-q', 'xp-n1', 'xp-80', 'xprinter'], note: _desk),

  // Rongta
  PrinterPreset(id: 'rongta_rpp02', brand: 'Rongta', model: 'RPP02N / RPP200', paper: 58, cut: false, cutMode: 'none', accents: false, match: ['rpp02', 'rpp2'], note: _mobile),
  PrinterPreset(id: 'rongta_rpp300', brand: 'Rongta', model: 'RPP300 / RPP320', paper: 80, cut: false, cutMode: 'none', accents: false, match: ['rpp3'], note: _mobile),
  PrinterPreset(id: 'rongta_rp80', brand: 'Rongta', model: 'RP80 / RP326 / RP327 (Bluetooth)', paper: 80, drawer: true, accents: false, match: ['rp80', 'rp32', 'rongta'], note: _desk),

  // HPRT
  PrinterPreset(id: 'hprt_mpt2', brand: 'HPRT', model: 'MPT-II / HM-E200', paper: 58, cut: false, cutMode: 'none', accents: false, match: ['mpt-ii', 'mpt-2', 'hm-e2'], note: _mobile),
  PrinterPreset(id: 'hprt_mpt3', brand: 'HPRT', model: 'MPT-3 / HM-E300', paper: 80, cut: false, cutMode: 'none', accents: false, match: ['mpt-3', 'hm-e3'], note: _mobile),
  PrinterPreset(id: 'hprt_tp805', brand: 'HPRT', model: 'TP805 / TP806 (Bluetooth)', paper: 80, drawer: true, accents: false, match: ['tp80', 'hprt'], note: _desk),

  // Goojprt
  PrinterPreset(id: 'goojprt_pt210', brand: 'Goojprt', model: 'PT-210 / MTP-II', paper: 58, cut: false, cutMode: 'none', accents: false, match: ['pt-210', 'mtp-ii', 'mtp-2', 'goojprt'], note: _mobile),
  PrinterPreset(id: 'goojprt_mtp3', brand: 'Goojprt', model: 'MTP-3', paper: 80, cut: false, cutMode: 'none', accents: false, match: ['mtp-3'], note: _mobile),

  // Autres marques chinoises courantes (ESC/POS générique)
  PrinterPreset(id: 'munbyn_58', brand: 'Munbyn', model: 'Portable 58 mm', paper: 58, cut: false, cutMode: 'none', accents: false, match: ['munbyn'], note: _mobile),
  PrinterPreset(id: 'munbyn_80', brand: 'Munbyn', model: 'Comptoir 80 mm (Bluetooth)', paper: 80, drawer: true, accents: false, note: _desk),
  PrinterPreset(id: 'netum_58', brand: 'Netum', model: 'NT-1809 / portable 58 mm', paper: 58, cut: false, cutMode: 'none', accents: false, match: ['nt-18', 'netum'], note: _mobile),
  PrinterPreset(id: 'netum_80', brand: 'Netum', model: 'Comptoir 80 mm (Bluetooth)', paper: 80, drawer: true, accents: false, note: _desk),
  PrinterPreset(id: 'zjiang_58', brand: 'Zjiang', model: 'ZJ-5802 / ZJ-5805 / ZJ-5890', paper: 58, cut: false, cutMode: 'none', accents: false, match: ['zj-58'], note: _mobile),
  PrinterPreset(id: 'zjiang_80', brand: 'Zjiang', model: 'ZJ-8001 / ZJ-8330 (80 mm)', paper: 80, drawer: true, accents: false, match: ['zj-8'], note: _desk),
  PrinterPreset(id: 'gainscha_58', brand: 'Gainscha / Gprinter', model: 'GP-58 (série)', paper: 58, cut: false, cutMode: 'none', accents: false, match: ['gp-58', 'gprinter'], note: _mobile),
  PrinterPreset(id: 'gainscha_80', brand: 'Gainscha / Gprinter', model: 'GP-80 (série)', paper: 80, drawer: true, accents: false, match: ['gp-80'], note: _desk),

  // Imprimante intégrée à la tablette
  PrinterPreset(id: 'sunmi_inner', brand: 'Sunmi', model: 'V2 / V2s / V2 Pro / P2 (intégrée)', paper: 58, cut: false, cutMode: 'none', match: ['innerprinter'],
      note: 'Choisissez l’appareil Bluetooth « InnerPrinter » (imprimante interne).'),
  PrinterPreset(id: 'sunmi_t2', brand: 'Sunmi', model: 'T2 / T2s (intégrée 80 mm)', paper: 80, drawer: true,
      note: 'Choisissez l’appareil Bluetooth « InnerPrinter » (imprimante interne).'),

  // Toute autre imprimante ESC/POS
  PrinterPreset(id: 'generic_58', brand: 'Autre', model: 'Autre imprimante 58 mm (POS-58, Printer001…)', paper: 58, cut: false, cutMode: 'none', accents: false,
      match: ['pos-58', 'pos58', 'printer001', 'bluetoothprinter', 'bluetooth printer', 'bt printer', 'mpt', 'pt-'], note: 'Réglage ESC/POS standard : faites le ticket test puis l’assistant.'),
  PrinterPreset(id: 'generic_80', brand: 'Autre', model: 'Autre imprimante 80 mm', paper: 80, drawer: true, accents: false, match: ['pos-80', 'pos80'],
      note: 'Réglage ESC/POS standard : faites le ticket test puis l’assistant.'),
];

List<String> get printerBrands {
  final out = <String>[];
  for (final p in printerPresets) {
    if (!out.contains(p.brand)) out.add(p.brand);
  }
  return out;
}

PrinterPreset presetById(String? id) => printerPresets.firstWhere((p) => p.id == id, orElse: () => printerPresets.firstWhere((p) => p.id == 'generic_58'));

/// Modèle reconnu d'après le nom Bluetooth de l'imprimante (le morceau le plus précis gagne).
PrinterPreset? detectPreset(String deviceName) {
  final name = deviceName.toLowerCase();
  PrinterPreset? best;
  var bestLength = 0;
  for (final p in printerPresets) {
    for (final m in p.match) {
      if (m.length > bestLength && name.contains(m)) {
        best = p;
        bestLength = m.length;
      }
    }
  }
  return best;
}

/// Réglage enregistré sur l'appareil (une imprimante par tablette).
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
    this.cutMode = 'feed',
    required this.drawer,
    this.drawerPin = 0,
    required this.accents,
    this.codePage = 16,
    this.barcode = true,
    this.copies = 1,
    this.autoPrint = true,
    this.keepAlive = true,
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
  String cutMode;
  bool drawer;
  int drawerPin;
  bool accents;
  int codePage;
  bool barcode;
  int copies;
  bool autoPrint;

  /// Bluetooth gardé connecté en permanence (reconnexion automatique).
  bool keepAlive;

  bool get ready => connection == 'network' ? host.isNotEmpty : address.isNotEmpty;

  String get summary {
    final where = connection == 'network' ? 'Réseau $host:$port' : 'Bluetooth ${deviceName.isNotEmpty ? deviceName : address}';
    return '${presetById(presetId).label} · $paper mm · $where';
  }

  factory PrinterConfig.fromPreset(PrinterPreset p) => PrinterConfig(
        presetId: p.id,
        connection: p.connection,
        paper: p.paper,
        columns: p.cols,
        cut: p.cut,
        cutMode: p.cutMode,
        drawer: p.drawer,
        drawerPin: p.drawerPin,
        accents: p.accents,
        codePage: p.codePage,
        barcode: p.barcode,
      );

  void applyPreset(PrinterPreset p) {
    presetId = p.id;
    if (connection != 'network') connection = p.connection;
    paper = p.paper;
    columns = p.cols;
    cut = p.cut;
    cutMode = p.cutMode;
    drawer = p.drawer;
    drawerPin = p.drawerPin;
    accents = p.accents;
    codePage = p.codePage;
    barcode = p.barcode;
  }

  factory PrinterConfig.fromJson(Map<String, dynamic> j) {
    final cut = j['cut'] != false;
    final page = (j['code_page'] as num? ?? 16).toInt();
    final mode = (j['cut_mode'] ?? '').toString();
    return PrinterConfig(
      presetId: (j['preset'] ?? 'generic_58').toString(),
      connection: (j['connection'] ?? 'bluetooth').toString(),
      address: (j['address'] ?? '').toString(),
      deviceName: (j['device_name'] ?? '').toString(),
      host: (j['host'] ?? '').toString(),
      port: (j['port'] as num? ?? 9100).toInt(),
      paper: (j['paper'] as num? ?? 80).toInt(),
      columns: (j['columns'] as num? ?? 48).toInt(),
      cut: cut,
      cutMode: cutModes.containsKey(mode) ? mode : (cut ? 'feed' : 'none'),
      drawer: j['drawer'] == true,
      drawerPin: (j['drawer_pin'] as num? ?? 0).toInt() == 1 ? 1 : 0,
      accents: j['accents'] != false,
      codePage: codePages.containsKey(page) ? page : 16,
      barcode: j['barcode'] != false,
      copies: (j['copies'] as num? ?? 1).toInt().clamp(1, 3),
      autoPrint: j['auto_print'] != false,
      keepAlive: j['keep_alive'] != false,
    );
  }

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
        'cut_mode': cutMode,
        'drawer': drawer,
        'drawer_pin': drawerPin,
        'accents': accents,
        'code_page': codePage,
        'barcode': barcode,
        'copies': copies,
        'auto_print': autoPrint,
        'keep_alive': keepAlive,
      };
}
