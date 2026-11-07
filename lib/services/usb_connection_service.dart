import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:easy_localization/easy_localization.dart';
import 'gcode_protocol.dart';
import 'pause_parking.dart';

class GridPoint {
  final int x, y;
  GridPoint(this.x, this.y);
  @override
  bool operator ==(Object other) =>
      other is GridPoint && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
}

class UsbConnectionService extends ChangeNotifier {
  UsbPort? _port;
  GcodeProtocol? _protocol;
  bool _connecting = false;
  Future<void>? _closing;
  bool _disposed = false;
  bool printActive = false;
  bool pauseMotionActive = false;
  final motionState = PrinterModalState();
  Object? lastError;

  bool get isConnected =>
      !_connecting && _protocol != null && !_protocol!.isClosed;
  bool get isConnecting => _connecting;
  bool get isIdle => _protocol?.isIdle ?? true;
  Stream<String> get lines => _protocol?.lines ?? const Stream.empty();

  Future<void> connect() async {
    if (_disposed || _connecting || isConnected || printActive) return;
    _connecting = true;
    lastError = null;
    notifyListeners();
    try {
      await _disconnect();
      final devices = await UsbSerial.listDevices();
      if (devices.isEmpty) throw GcodeException('USB_is_not_connected'.tr());
      final port = await devices.first.create();
      _port = port;
      if (port == null || !await port.open()) {
        throw GcodeException('USB_is_not_connected'.tr());
      }
      if (_disposed) {
        await port.close();
        return;
      }
      await port.setDTR(true);
      await port.setRTS(true);
      await port.setPortParameters(
          115200, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);
      final input = port.inputStream;
      if (input == null) throw GcodeException('USB input unavailable');
      _protocol = GcodeProtocol(
        input: input,
        numbered: true,
        write: (data) => port.write(Uint8List.fromList(data)),
        onFault: (error) {
          lastError = error;
          _disconnect();
        },
      );
      // DTR may reset the printer. Drain startup output before the handshake.
      await Future<void>.delayed(const Duration(seconds: 2));
      if (_disposed) {
        await _disconnect();
        return;
      }
      final protocol = _protocol;
      if (protocol == null) throw GcodeException('USB disconnected');
      await protocol.initializeNumbering();
      await protocol.send('M105');
      // Establish modes and a known runtime idle timeout; reconnect need not reset firmware.
      for (final command in ['G21', 'G90', 'M82', 'M84 S120']) {
        await protocol.send(command);
        motionState.acknowledge(command);
      }
    } catch (error) {
      lastError = error;
      await _disconnect();
      rethrow;
    } finally {
      _connecting = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _disconnect() => _closing ??= _closePort();

  Future<void> _closePort() async {
    final protocol = _protocol;
    final port = _port;
    _protocol = null;
    _port = null;
    motionState.reset();
    protocol?.close();
    if (!_disposed) notifyListeners();
    try {
      await port?.close();
    } catch (_) {
      // Detaching a USB device can also make its close call fail.
    } finally {
      _closing = null;
    }
  }

  Future<List<String>> execute(String command, {bool fromPrint = false}) {
    if (!isConnected) return Future.error(GcodeException('USB disconnected'));
    final code = command.trim().split(RegExp(r'\s+')).first.toUpperCase();
    if (pauseMotionActive && !fromPrint && code == 'M851') {
      return Future.error(GcodeException('Printer_busy'.tr()));
    }
    if (printActive &&
        !fromPrint &&
        !{'M104', 'M105', 'M140', 'M106', 'M107', 'M851', 'M115', 'M78'}
            .contains(code)) {
      return Future.error(GcodeException('Printer_busy'.tr()));
    }
    return _protocol!.send(command).then((response) {
      motionState.acknowledge(command);
      return response;
    });
  }

  Future<void> sendGCode(String commands, BuildContext context) async {
    try {
      // Keep multi-line manual operations together in the same FIFO.
      final requests = commands
          .split(RegExp(r'[\r\n]+'))
          .where((line) => line.trim().isNotEmpty)
          .map((line) => execute(line))
          .toList();
      await Future.wait(requests);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<bool> awaitGcode(String command, BuildContext context) async {
    try {
      await execute(command);
      return true;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
      return false;
    }
  }

  Future<bool> startBL(BuildContext context) async {
    if (!await awaitGcode('G28', context) || !context.mounted) return false;
    return awaitGcode('G29', context);
  }

  Future<String> _query(String command, BuildContext context) async {
    try {
      return (await execute(command)).join('\n');
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
      return '';
    }
  }

  Future<Map<String, String?>> getFWInfo(BuildContext context) async {
    final raw = await _query('M115', context);
    final result = <String, String?>{};
    const fields = {
      'Firmware': 'FIRMWARE_NAME',
      'Source_Code': 'SOURCE_CODE_URL',
      'Protocol_Version': 'PROTOCOL_VERSION',
      'Machine_Type': 'MACHINE_TYPE',
      'Extruder_Count': 'EXTRUDER_COUNT',
      'UUID': 'UUID',
    };
    for (final field in fields.entries) {
      result[field.key] =
          RegExp('${field.value}:(.*?)(?=\\s+[A-Z_]+:|\\r?\\n|\$)')
                  .firstMatch(raw)
                  ?.group(1)
                  ?.trim() ??
              '-';
    }
    return result;
  }

  Future<Map<String, String?>> getStats(BuildContext context) async {
    final raw = await _query('M78', context);
    final result = <String, String?>{};
    const fields = {
      'Prints': r'Prints:\s*(\d+)',
      'Finished': r'Finished:\s*(\d+)',
      'Failed': r'Failed:\s*(\d+)',
      'Total_time': r'Total time:\s*([^\r\n]+)',
      'Longest_job': r'Longest job:\s*([^\r\n]+)',
      'Filament_used': r'Filament used:\s*([0-9.]+\s*m)',
    };
    for (final field in fields.entries) {
      result[field.key] = RegExp(field.value).firstMatch(raw)?.group(1) ?? '-';
    }
    return result;
  }

  Future<Map<GridPoint, double>> getBLGrid(BuildContext context) async =>
      parseBedGrid(await _query('M420 V', context));

  static Map<GridPoint, double> parseBedGrid(String raw) {
    final start = raw.indexOf('Bilinear Leveling Grid:');
    if (start < 0) return {};
    final rows = <int, List<double>>{};
    for (final line in raw.substring(start).split('\n').skip(1)) {
      if (line.contains('Subdivided')) break;
      // Data rows have signed or decimal heights; skip integer column labels.
      final match =
          RegExp(r'^\s*(\d+)\s+((?:[+-]?\d*\.\d+\s*)+)$').firstMatch(line);
      if (match == null) continue;
      final values = match
          .group(2)!
          .trim()
          .split(RegExp(r'\s+'))
          .map(double.parse)
          .toList();
      rows[int.parse(match.group(1)!)] = values;
    }
    if (rows.isEmpty) return {};
    final width = rows.values.first.length;
    final indices = rows.keys.toList()..sort();
    if (width < 2 ||
        rows.length < 2 ||
        rows.values.any((row) => row.length != width) ||
        List.generate(rows.length, (i) => i).any((i) => indices[i] != i)) {
      return {};
    }
    return {
      for (final row in rows.entries)
        for (int x = 0; x < width; x++) GridPoint(x, row.key): row.value[x]
    };
  }

  @override
  void dispose() {
    _disposed = true;
    _disconnect();
    super.dispose();
  }
}
