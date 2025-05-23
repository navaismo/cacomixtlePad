import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:easy_localization/easy_localization.dart';

/// Holds a point in integer grid space
class GridPoint {
  final int x, y;
  GridPoint(this.x, this.y);
  @override
  bool operator ==(other) => other is GridPoint && other.x == x && other.y == y;
  @override
  int get hashCode => x.hashCode ^ y.hashCode;
  @override
  String toString() => '($x,$y)';
}

class UsbConnectionService extends ChangeNotifier {
  UsbPort? _port;
  bool _isConnected = false;
  Timer? _timeoutTimer;
  bool waitingForOk = false;

  UsbPort? get port => _port;
  bool get isConnected => _isConnected;

  Future<void> connect() async {
    List<UsbDevice> devices = await UsbSerial.listDevices();
    if (devices.isEmpty) {
      _setDisconnected();
      return;
    }

    _port = await devices[0].create();
    bool openResult = await _port!.open();
    if (!openResult) {
      _setDisconnected();
      return;
    }

    await _port!.setDTR(true);
    await _port!.setRTS(true);
    await _port!.setPortParameters(
      115200,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );

    _port!.inputStream?.listen(_onDataReceived, onDone: _onDisconnected);
    _setConnected();
  }

  void _onDataReceived(Uint8List data) {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 10), _onDisconnected);
  }

  void _onDisconnected() {
    _setDisconnected();
  }

  void _setConnected() {
    _isConnected = true;
    notifyListeners();
  }

  void _setDisconnected() {
    _isConnected = false;
    _port?.close();
    _port = null;
    notifyListeners();
  }

  void sendGCode(String command, BuildContext context) {
    if (_port != null && _isConnected) {
      _port!.write(Uint8List.fromList("$command\n".codeUnits));
    } else {
      Future.delayed(const Duration(milliseconds: 300), () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('USB_is_not_connected'.tr()),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('OK'.tr()),
              ),
            ],
          ),
        );
      });
    }
  }

  Future<bool> awaitGcode(String command, BuildContext context) async {
    if (_port != null && _isConnected && !kDebugMode && !waitingForOk) {
      final completer = Completer<bool>();
      waitingForOk = true;

      Timer? timeoutTimer;
      StreamSubscription? subscription;

      void resetTimeout() {
        timeoutTimer?.cancel();
        timeoutTimer = Timer(const Duration(seconds: 10), () {
          subscription?.cancel();
          waitingForOk = false;
          if (!completer.isCompleted) completer.complete(false);
        });
      }

      subscription = _port!.inputStream?.listen((data) {
        final response = String.fromCharCodes(data);
        debugPrint("USB_RESPONSE: $response");

        if (response.contains('ok')) {
          waitingForOk = false;
          timeoutTimer?.cancel();
          subscription?.cancel();
          if (!completer.isCompleted) completer.complete(true);
        } else if (response.contains('Error') || response.contains('fail')) {
          waitingForOk = false;
          timeoutTimer?.cancel();
          subscription?.cancel();
          if (!completer.isCompleted) completer.complete(false);
        } else {
         
          resetTimeout();
        }
      });

      // Send command
      _port!.write(Uint8List.fromList("$command\n".codeUnits));

      // Start timeout
      resetTimeout();

      return completer.future;
    } else if (kDebugMode) {
      print("Debug mode");
      return true;
    } else {
      Future.delayed(const Duration(milliseconds: 300), () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('USB_is_not_connected'.tr()),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('OK'.tr()),
              ),
            ],
          ),
        );
      });
      return false;
    }
  }

  Future<bool> startBL(BuildContext context) async {
    // Helper to send command and await response
    Future<bool> sendAndAwait(String cmd) async {
      return await awaitGcode(cmd, context);
    }

    // Home, Start BL
    if (await sendAndAwait("G28") && await sendAndAwait("G29")) {
      return true;
    }
    return false;
  }

  Future<Map<String, String?>> getFWInfo(BuildContext context) async {
    Map<String, String?> obj = {};

    if (_port != null && _isConnected && !kDebugMode) {
      final completer = Completer<String>();
      StreamSubscription? subscription;

      subscription = _port!.inputStream?.listen((data) {
        final decoded = String.fromCharCodes(data);
        if (decoded.contains('FIRMWARE_NAME:')) {
          completer.complete(decoded);
          subscription?.cancel();
        }
      });

      // Send M115 command
      await _port!.write(Uint8List.fromList("M115\n".codeUnits));

      String decoded;
      try {
        decoded = await completer.future.timeout(const Duration(seconds: 2));
      } catch (_) {
        decoded = '';
      }

      final firmwareNameRegex = RegExp(r'FIRMWARE_NAME:(.*?)(?:\s|$)');
      final sourceCodeUrlRegex = RegExp(r'SOURCE_CODE_URL:(.*?)(?:\s|$)');
      final protocolVersionRegex = RegExp(r'PROTOCOL_VERSION:(.*?)(?:\s|$)');
      final machineTypeRegex =
          RegExp(r'MACHINE_TYPE:(.*?)(?=\s+EXTRUDER_COUNT:)');
      final extruderCountRegex = RegExp(r'EXTRUDER_COUNT:(.*?)(?:\s|$)');
      final uuidRegex = RegExp(r'UUID:(.*?)(?:\s|$)');

      final firmwareNameMatch = firmwareNameRegex.firstMatch(decoded);
      final sourceCodeUrlMatch = sourceCodeUrlRegex.firstMatch(decoded);
      final protocolVersionMatch = protocolVersionRegex.firstMatch(decoded);
      final machineTypeMatch = machineTypeRegex.firstMatch(decoded);
      final extruderCountMatch = extruderCountRegex.firstMatch(decoded);
      final uuidMatch = uuidRegex.firstMatch(decoded);

      obj = {
        'Firmware': firmwareNameMatch != null
            ? firmwareNameMatch.group(1)
            : 'FW Unknown',
        'Source_Code': sourceCodeUrlMatch != null
            ? sourceCodeUrlMatch.group(1)
            : 'URL Unknown',
        'Protocol_Version': protocolVersionMatch != null
            ? protocolVersionMatch.group(1)
            : 'Protocol Unknown',
        'Machine_Type': machineTypeMatch != null
            ? machineTypeMatch.group(1)
            : 'Machine Unknown',
        'Extruder_Count': extruderCountMatch != null
            ? extruderCountMatch.group(1)
            : 'Extruder Unknown',
        'UUID': uuidMatch != null ? uuidMatch.group(1) : 'UUID Unknown',
      };

      return obj;
    } else if (kDebugMode) {
      obj = {
        "Firmware": "FW Debug 1.1",
        "Source_Code": "URL Debug some.url.com",
        "Protocol_Version": "Protocl Debug 1.0",
        "Machine_Type": "Machine Debug Model",
        "Extruder_Count": "Extruder Debug 1",
        "UUID": "UUID Debug 123456",
      };
      return obj;
    } else {
      Future.delayed(const Duration(milliseconds: 300), () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('USB_is_not_connected'.tr()),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('OK'.tr()),
              ),
            ],
          ),
        );
      });
      return {};
    }
  }

  Future<Map<String, String?>> getStats(BuildContext context) async {
    Map<String, String?> obj = {};

    if (_port != null && _isConnected && !kDebugMode) {
      final completer = Completer<String>();
      StreamSubscription? subscription;

      subscription = _port!.inputStream?.listen((data) {
        final decoded = String.fromCharCodes(data);
        if (decoded.contains('Filament')) {
          completer.complete(decoded);
          subscription?.cancel();
        }
      });

      // Send M78 command
      await _port!.write(Uint8List.fromList("M78\n".codeUnits));

      String decoded;
      try {
        decoded = await completer.future.timeout(const Duration(seconds: 2));
      } catch (_) {
        decoded = '';
      }

      final prints = RegExp(r'Prints:\s*(\d+)');
      final finished = RegExp(r'Finished:\s*(\d+)');
      final failed = RegExp(r'Failed:\s*(\d+)');
      final totaltime = RegExp(
          r'Total time:\s*(\d+)\s*d\s*(\d+)\s*h\s*(\d+)\s*m\s*(\d+)\s*s');
      final longestjob = RegExp(
          r'Longest job:\s*(\d+)\s*d\s*(\d+)\s*h\s*(\d+)\s*m\s*(\d+)\s*s');
      final filamentused = RegExp(r'Filament used:\s*([0-9]+(?:\.[0-9]+)?)m');

      final printsMatch = prints.firstMatch(decoded);
      final finishedMatch = finished.firstMatch(decoded);
      final failedMatch = failed.firstMatch(decoded);
      final totaltimeMatch = totaltime.firstMatch(decoded);
      final longestjobMatch = longestjob.firstMatch(decoded);
      final filamentusedMatch = filamentused.firstMatch(decoded);

      obj = {
        'Prints': printsMatch != null ? printsMatch.group(1) : 'Prints Unknown',
        'Finished':
            finishedMatch != null ? finishedMatch.group(1) : 'Finished Unknown',
        'Failed': failedMatch != null ? failedMatch.group(1) : 'Failed Unknown',
        'Total_time': totaltimeMatch != null
            ? '${totaltimeMatch.group(1)}d ${totaltimeMatch.group(2)}h ${totaltimeMatch.group(3)}m ${totaltimeMatch.group(4)}s'
            : 'Total time Unknown',
        'Longest_job': longestjobMatch != null
            ? '${longestjobMatch.group(1)}d ${longestjobMatch.group(2)}h ${longestjobMatch.group(3)}m ${longestjobMatch.group(4)}s'
            : 'Longest job Unknown',
        'Filament_used':
            filamentusedMatch != null && filamentusedMatch.group(1) != null
                ? filamentusedMatch.group(1)! + 'm'
                : 'Filament used Unknown',
      };

      return obj;
    } else if (kDebugMode) {
      print("Debug mode");
      obj = {
        'Prints': '726',
        'Finished': '380',
        'Failed': '346',
        'Total_time': '76d 13h 59m 42s',
        'Longest_job': '1d 8h 31m 18s',
        'Filament_used': '4030.23m',
      };

      return obj;
    } else {
      Future.delayed(const Duration(milliseconds: 300), () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('USB_is_not_connected'.tr()),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('OK'.tr()),
              ),
            ],
          ),
        );
      });
      return {};
    }
  }

  Future<Map<GridPoint, double>> getBLGrid(BuildContext context) async {
    String raw;

    if (_port != null && _isConnected && !kDebugMode) {
      final completer = Completer<String>();
      final buffer = StringBuffer();
      StreamSubscription? subscription;

      subscription = _port!.inputStream?.listen((data) {
        final decoded = String.fromCharCodes(data);
        buffer.write(decoded);

        if (buffer
            .toString()
            .contains("Subdivided with CATMULL ROM Leveling Grid:")) {
          subscription?.cancel();
          completer.complete(buffer.toString());
        }
      });

      await _port!.write(Uint8List.fromList('M420 V\n'.codeUnits));

      try {
        raw = await completer.future.timeout(const Duration(seconds: 3));
      } catch (_) {
        raw = '';
      }
    } else if (kDebugMode) {
      raw = '''
Bilinear Leveling Grid:
    0      1      2      3      4      5      6
0 -0.084 -0.089 -0.100 -0.110 -0.115 -0.128 -0.121
1 -0.090 -0.064 -0.080 -0.086 -0.103 -0.106 -0.093
2 -0.081 -0.061 -0.090 -0.101 -0.108 -0.106 -0.109
3 -0.080 -0.090 -0.094 -0.093 -0.090 -0.099 -0.085
4 -0.086 -0.062 -0.065 -0.060 -0.066 -0.050 -0.030
5 -0.083 -0.038 -0.025 -0.034 -0.037 -0.015 -0.015
6 -0.021 -0.020 -0.018 -0.019 -0.011 -0.012 -0.017
Subdivided with CATMULL ROM Leveling Grid:
''';
    } else {
      Future.delayed(const Duration(milliseconds: 300), () {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.error, color: Colors.red),
                const SizedBox(width: 8),
                Text('USB_is_not_connected'.tr()),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('OK'.tr()),
              ),
            ],
          ),
        );
      });
      return {};
    }

    final startIndex = raw.indexOf('Bilinear Leveling Grid:');
    final endIndex = raw.indexOf('Subdivided with CATMULL ROM Leveling Grid:');

    if (startIndex == -1 || endIndex == -1 || endIndex <= startIndex) {
      return {};
    }

    final gridBlock = raw.substring(startIndex, endIndex);
    final lines = gridBlock
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && RegExp(r'^\d+').hasMatch(l))
        .toList();

    final Map<GridPoint, double> gridMap = {};

    for (final line in lines) {
      final parts = line.split(RegExp(r'\s+'));
      final y = int.tryParse(parts[0]);
      if (y == null) continue;

      for (int x = 0; x < parts.length - 1; x++) {
        final z = double.tryParse(parts[x + 1]);
        if (z != null) {
          gridMap[GridPoint(x, y)] = z;
        }
      }
    }

    if (kDebugMode) {
      print(" >>>>>>>>> GridMap: $gridMap");
    }

    return gridMap;
  }

  void disposeService() {
    _timeoutTimer?.cancel();
    _port?.close();
    _port = null;
    _isConnected = false;
    notifyListeners();
  }
}
