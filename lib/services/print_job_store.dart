import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

abstract class PrintJobStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> snapshot);
}

class PreferencesPrintJobStore implements PrintJobStore {
  static const key = 'last_print_job_v1';

  @override
  Future<Map<String, dynamic>?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(key);
    if (json == null) return null;
    final value = jsonDecode(json);
    if (value is! Map<String, dynamic> || value['schema'] != 1) {
      throw const FormatException('Invalid print history');
    }
    return value;
  }

  @override
  Future<void> write(Map<String, dynamic> snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, jsonEncode(snapshot))) {
      throw StateError('Unable to save print history');
    }
  }
}
