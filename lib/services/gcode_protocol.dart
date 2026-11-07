import 'dart:async';
import 'dart:collection';
import 'dart:convert';

class GcodeException implements Exception {
  final String message;
  GcodeException(this.message);
  @override
  String toString() => message;
}

class _Command {
  final String text;
  final int? number;
  final completer = Completer<List<String>>();
  final responses = <String>[];
  int retries = 0;
  _Command(this.text, [this.number]);

  List<int> get bytes {
    if (number == null) return utf8.encode('$text\n');
    final payload = utf8.encode('N$number $text');
    final checksum = payload.fold<int>(0, (value, byte) => value ^ byte);
    return [...payload, ...ascii.encode('*$checksum\n')];
  }
}

/// One writer and one line parser for the entire serial connection.
/// An unrecoverable protocol fault invalidates the session: late ACKs cannot acknowledge a
/// different command. Reconnect before sending again after such a fault.
class GcodeProtocol {
  final Future<void> Function(List<int>) write;
  final Duration ackTimeout;
  final Duration commandTimeout;
  final bool numbered;
  final int maxRetries;
  final void Function(Object)? onFault;
  final _queue = Queue<_Command>();
  final _lines = StreamController<String>.broadcast(sync: true);
  StreamSubscription<List<int>>? _subscription;
  _Command? _active;
  Timer? _ackTimer;
  Timer? _commandTimer;
  String _buffer = '';
  bool _closed = false;
  bool _pumpScheduled = false;
  bool _numberingInitialized = false;
  int _nextNumber = 1;
  bool _awaitingResend = false;
  int? _requestedNumber;
  bool _retryScheduled = false;
  bool _hasSent = false;

  GcodeProtocol({
    required Stream<List<int>> input,
    required this.write,
    this.ackTimeout = const Duration(seconds: 10),
    this.commandTimeout = const Duration(minutes: 30),
    this.numbered = false,
    this.maxRetries = 3,
    this.onFault,
  }) {
    _subscription = input.listen(_receive,
        onError: (Object error) => _fail(error),
        onDone: () => _fail(GcodeException('USB disconnected')));
  }

  Stream<String> get lines => _lines.stream;
  bool get isIdle => _active == null && _queue.isEmpty;
  bool get isClosed => _closed;

  /// Call once after startup and before accepting application commands.
  Future<void> initializeNumbering() async {
    if (!numbered || _numberingInitialized) return;
    if (_closed || !isIdle) {
      throw GcodeException('Cannot reset an active session');
    }
    final reset = _Command('M110 N0', 0);
    _queue.add(reset);
    _schedulePump();
    await reset.completer.future;
    _numberingInitialized = true;
  }

  Future<List<String>> send(String command) {
    if (_closed) return Future.error(GcodeException('USB disconnected'));
    if (numbered && !_numberingInitialized) {
      return Future.error(GcodeException('Line numbering is not initialized'));
    }
    final text = command.split(';').first.trim();
    if (text.contains('\n') || text.contains('\r')) {
      return Future.error(ArgumentError('Send one G-code line at a time'));
    }
    if (text.isEmpty) return Future.value(<String>[]);
    if (numbered &&
        RegExp(r'^(?:N\d+|M110(?=\D|$))', caseSensitive: false)
            .hasMatch(text)) {
      return Future.error(
          GcodeException('Line numbering is managed by the connection'));
    }
    final request = _Command(text, numbered ? _nextNumber++ : null);
    _queue.add(request);
    _schedulePump();
    return request.completer.future;
  }

  void _schedulePump() {
    if (_pumpScheduled || _closed) return;
    _pumpScheduled = true;
    // Finish processing the current USB packet before sending another line.
    // Extra ACKs in that packet must not complete a command not yet written.
    scheduleMicrotask(() {
      _pumpScheduled = false;
      _pump();
    });
  }

  Future<void> _pump() async {
    if (_closed || _active != null || _queue.isEmpty) return;
    final request = _queue.removeFirst();
    _active = request;
    _hasSent = true;
    _armAckTimer();
    _commandTimer = Timer(
        commandTimeout,
        () => _fail(
            GcodeException('Command exceeded time limit: ${request.text}')));
    try {
      await write(request.bytes);
    } catch (error) {
      _fail(error);
    }
  }

  void _armAckTimer() {
    _ackTimer?.cancel();
    _ackTimer = Timer(ackTimeout,
        () => _fail(GcodeException('No ACK received; reconnect the printer')));
  }

  void _receive(List<int> bytes) {
    if (_closed) return;
    _buffer += latin1.decode(bytes);
    if (_buffer.length > 65536) {
      _fail(GcodeException('Serial response exceeded line limit'));
      return;
    }
    while (!_closed) {
      final end = _buffer.indexOf(RegExp(r'[\r\n]'));
      if (end < 0) break;
      final line = _buffer.substring(0, end).trim();
      _buffer = _buffer.substring(end + 1);
      if (line.isEmpty) continue;
      _lines.add(line);
      final request = _active;
      final lineError = RegExp(
              r'^Error:(?:checksum mismatch|Line Number is not Last Line Number\+1|No Checksum with line number),\s*Last Line:\s*(\d+)\s*$',
              caseSensitive: false)
          .firstMatch(line);
      if (numbered &&
          lineError != null &&
          request?.number != null &&
          int.parse(lineError.group(1)!) == request!.number! - 1) {
        if (_retryScheduled) continue;
        _awaitingResend = true;
        _requestedNumber = null;
        _armAckTimer();
        continue;
      }
      final resend =
          RegExp(r'^(?:Resend:\s*|rs\s+)(?:N)?(\d+)\s*$', caseSensitive: false)
              .firstMatch(line);
      if (resend != null && numbered && request?.number != null) {
        final number = int.parse(resend.group(1)!);
        if (number != request!.number) {
          _fail(GcodeException('Cannot recover requested line $number'));
          return;
        }
        if (_retryScheduled) continue;
        if (request.retries >= maxRetries) {
          _fail(GcodeException('Retry limit exceeded for line $number'));
          return;
        }
        _awaitingResend = true;
        _requestedNumber = number;
        _armAckTimer();
        continue;
      }
      if (RegExp(r'^(?:Error:|!!|Resend:|rs\b)', caseSensitive: false)
              .hasMatch(line) ||
          (line == 'start' && _hasSent)) {
        _fail(GcodeException(line));
        return;
      }
      if (request == null) continue;
      if (_retryScheduled) continue;
      if (_awaitingResend) {
        // Marlin ends Error/Resend with a transport ACK. Consume it before
        // retransmitting, even when it arrives in a separate USB packet.
        if (_requestedNumber != null && RegExp(r'^ok(?:\s|$)').hasMatch(line)) {
          _awaitingResend = false;
          _requestedNumber = null;
          _retryScheduled = true;
          request.retries++;
          scheduleMicrotask(() async {
            _retryScheduled = false;
            if (_closed || _active != request) return;
            _armAckTimer();
            try {
              await write(request.bytes);
            } catch (error) {
              _fail(error);
            }
          });
        }
        continue;
      }
      request.responses.add(line);
      if (RegExp(r'^ok(?:\s|$)', caseSensitive: false).hasMatch(line)) {
        final acknowledged =
            RegExp(r'^ok\s+N(\d+)\b', caseSensitive: false).firstMatch(line);
        if (request.number != null &&
            acknowledged != null &&
            int.parse(acknowledged.group(1)!) != request.number) {
          _fail(GcodeException('ACK has an unexpected line number'));
          return;
        }
        _ackTimer?.cancel();
        _commandTimer?.cancel();
        _active = null;
        request.completer.complete(List.unmodifiable(request.responses));
        _schedulePump();
      } else if (RegExp(r'busy:|^wait$|(?:^|\s)[TB]:', caseSensitive: false)
          .hasMatch(line)) {
        // Marlin reports keepalive/temperature while homing, probing or heating.
        _armAckTimer();
      }
    }
  }

  void _fail(Object error) {
    if (_closed) return;
    close(error);
    onFault?.call(error);
  }

  void close([Object? reason]) {
    if (_closed) return;
    _closed = true;
    _ackTimer?.cancel();
    _commandTimer?.cancel();
    _subscription?.cancel();
    final error = reason ?? GcodeException('USB disconnected');
    _active?.completer.completeError(error);
    _active = null;
    while (_queue.isNotEmpty) {
      _queue.removeFirst().completer.completeError(error);
    }
    // A fault can occur while the synchronous lines stream is dispatching.
    scheduleMicrotask(_lines.close);
  }
}
