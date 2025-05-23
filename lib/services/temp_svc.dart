// lib/services/temperature_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';

class TemperatureService extends ChangeNotifier {
  static final TemperatureService _instance = TemperatureService._internal();
  factory TemperatureService() => _instance;
  TemperatureService._internal();

  UsbPort? _port;
  Timer? _timer;

  String hotendTemp = '--';
  String bedTemp = '--';
  double targetHotend = 0;
  double targetBed = 0;
  int fanSpeed = 0;

  void start(UsbPort port) {
    _port = port;
    _startPolling();
  }

  void stop() {
    _timer?.cancel();
    _port = null;
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _requestTemperatures());
  }

  void _requestTemperatures() {
    if (_port == null) return;
    _port!.write(Uint8List.fromList("M105\n".codeUnits));
    _port!.inputStream?.listen((data) {
      final decoded = String.fromCharCodes(data);
      final tempRegex = RegExp(
         r'T:(\d+(?:\.\d+)?)\s*/\s*(\d+(?:\.\d+)?)\s*B:(\d+(?:\.\d+)?)\s*/\s*(\d+(?:\.\d+)?)');
      final fanRegex = RegExp(r'FAN0@:(\d+)');

      final match = tempRegex.firstMatch(decoded);
      final fanMatch = fanRegex.firstMatch(decoded);

      if (match != null) {
        hotendTemp = match.group(1)!;
        targetHotend = double.tryParse(match.group(2) ?? '0') ?? 0;
        bedTemp = match.group(3)!;
        targetBed = double.tryParse(match.group(4) ?? '0') ?? 0;
        notifyListeners();
      }

      if (fanMatch != null) {
        fanSpeed = int.tryParse(fanMatch.group(1) ?? '0') ?? 0;
      }
    });
  }
}
