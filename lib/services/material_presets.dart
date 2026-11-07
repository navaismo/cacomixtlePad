import 'package:shared_preferences/shared_preferences.dart';

class MaterialPresets {
  static const materials = ['PLA', 'PETG', 'TPU', 'ABS'];
  static const hotend = {
    'PLA': 200.0,
    'PETG': 240.0,
    'TPU': 220.0,
    'ABS': 270.0
  };
  static const bed = {'PLA': 60.0, 'PETG': 72.0, 'TPU': 65.0, 'ABS': 90.0};

  static double read(SharedPreferences prefs, String material,
      {required bool isBed}) {
    final value = prefs.getDouble('${isBed ? 'bed' : 'hotend'}_$material');
    return value != null &&
            value.isFinite &&
            value >= 0 &&
            value <= (isBed ? 150 : 300)
        ? value
        : (isBed ? bed : hotend)[material]!;
  }
}
