import 'dart:async';
import 'dart:convert';
import 'package:CacomixtlePad/services/gcode_protocol.dart';
import 'package:CacomixtlePad/services/usb_connection_service.dart';

class FakePrinter extends UsbConnectionService {
  final input = StreamController<List<int>>(sync: true);
  final sent = <String>[];
  late final GcodeProtocol protocol;
  bool connected = true;
  FakePrinter({bool numbered = false}) {
    protocol = GcodeProtocol(
        input: input.stream,
        numbered: numbered,
        write: (data) async {
          sent.add(utf8.decode(data).trim());
        },
        onFault: (_) {
          connected = false;
          notifyListeners();
        });
  }
  @override
  bool get isConnected => connected && !protocol.isClosed;
  @override
  bool get isIdle => protocol.isIdle;
  @override
  Stream<String> get lines => protocol.lines;
  @override
  Future<List<String>> execute(String command, {bool fromPrint = false}) =>
      protocol.send(command);
  void respond([String text = 'ok\n']) => input.add(utf8.encode(text));
  void detach() {
    connected = false;
    protocol.close();
    notifyListeners();
  }

  @override
  void dispose() {
    protocol.close();
    input.close();
    super.dispose();
  }
}

Future<void> until(bool Function() condition) async {
  for (int i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('Condition did not become true');
}
