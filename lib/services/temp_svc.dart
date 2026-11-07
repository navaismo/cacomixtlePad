import 'dart:async';
import 'package:flutter/foundation.dart';
import 'usb_connection_service.dart';

class TemperatureService extends ChangeNotifier {
  final UsbConnectionService connection;
  StreamSubscription<String>? _subscription;
  Timer? _timer;
  bool _polling = false;
  bool _disposed = false;

  String hotendTemp = '--';
  String bedTemp = '--';
  double targetHotend = 0;
  double targetBed = 0;
  int fanSpeed = 0;

  TemperatureService(this.connection) {
    connection.addListener(_syncConnection);
    _syncConnection();
  }

  void _syncConnection() {
    stop();
    if (!connection.isConnected || connection.isConnecting) {
      hotendTemp = bedTemp = '--';
      if (!_disposed) notifyListeners();
      return;
    }
    _subscription = connection.lines.listen(_onLine);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    _poll();
  }

  Future<void> _poll() async {
    // At most one queued poll; long commands can still emit temperature reports.
    if (_polling || !connection.isConnected) return;
    _polling = true;
    try {
      await connection.execute('M105');
    } catch (_) {
      // The connection reports protocol failures and fails any active job.
    } finally {
      _polling = false;
    }
  }

  void _onLine(String line) {
    final hotend =
        RegExp(r'(?:^|\s)T:([+-]?[\d.]+)\s*/\s*([\d.]+)').firstMatch(line);
    final bed =
        RegExp(r'(?:^|\s)B:([+-]?[\d.]+)\s*/\s*([\d.]+)').firstMatch(line);
    final fan = RegExp(r'FAN0@:(\d+)').firstMatch(line);
    if (hotend != null) {
      hotendTemp = hotend.group(1)!;
      targetHotend = double.tryParse(hotend.group(2)!) ?? targetHotend;
    }
    if (bed != null) {
      bedTemp = bed.group(1)!;
      targetBed = double.tryParse(bed.group(2)!) ?? targetBed;
    }
    if (fan != null) fanSpeed = int.parse(fan.group(1)!);
    if (!_disposed && (hotend != null || bed != null || fan != null)) {
      notifyListeners();
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    _disposed = true;
    connection.removeListener(_syncConnection);
    stop();
    super.dispose();
  }
}
