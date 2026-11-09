import 'package:shared_preferences/shared_preferences.dart';

/// Réglages gardés sur cet appareil (poste de préparation).
class PrepSettings {
  PrepSettings(this._prefs);

  final SharedPreferences _prefs;

  /// 0 = adaptée au livreur, 6 = 10 × 15, 5 = 10 × 10.
  int get labelFormat => _prefs.getInt('label_format') ?? 0;
  set labelFormat(int v) => _prefs.setInt('label_format', v);

  int get copies => (_prefs.getInt('copies') ?? 1).clamp(1, 5);
  set copies(int v) => _prefs.setInt('copies', v.clamp(1, 5));

  /// android = impression Android (choix de l'imprimante) ; network / bluetooth = imprimante d'étiquettes TSPL, sans clic.
  String get printMode => _prefs.getString('print_mode') ?? 'android';
  set printMode(String v) => _prefs.setString('print_mode', v);

  String get host => _prefs.getString('printer_host') ?? '';
  set host(String v) => _prefs.setString('printer_host', v.trim());

  int get port => _prefs.getInt('printer_port') ?? 9100;
  set port(int v) => _prefs.setInt('printer_port', v);

  String get btAddress => _prefs.getString('bt_address') ?? '';
  set btAddress(String v) => _prefs.setString('bt_address', v);

  String get btName => _prefs.getString('bt_name') ?? '';
  set btName(String v) => _prefs.setString('bt_name', v);

  /// Densité de l'imprimante d'étiquettes : 8 points par mm (203 dpi) ou 12 (300 dpi).
  int get dotsPerMm => _prefs.getInt('dots_per_mm') ?? 8;
  set dotsPerMm(int v) => _prefs.setInt('dots_per_mm', v == 12 ? 12 : 8);

  bool get autoPrint => _prefs.getBool('auto_print') ?? true;
  set autoPrint(bool v) => _prefs.setBool('auto_print', v);

  bool get autoFinish => _prefs.getBool('auto_finish') ?? true;
  set autoFinish(bool v) => _prefs.setBool('auto_finish', v);

  bool get sound => _prefs.getBool('sound') ?? true;
  set sound(bool v) => _prefs.setBool('sound', v);

  bool get keepAwake => _prefs.getBool('keep_awake') ?? true;
  set keepAwake(bool v) => _prefs.setBool('keep_awake', v);

  String get stationName => _prefs.getString('station_name') ?? '';
  set stationName(String v) => _prefs.setString('station_name', v.trim());

  bool get directReady => printMode == 'network' ? host.isNotEmpty : (printMode == 'bluetooth' ? btAddress.isNotEmpty : true);
}
