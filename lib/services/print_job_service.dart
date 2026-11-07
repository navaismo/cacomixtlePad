import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'gcode_repository.dart';
import 'usb_connection_service.dart';
import 'print_job_store.dart';

enum PrintState {
  idle,
  loading,
  printing,
  paused,
  cancelling,
  completed,
  cancelled,
  failed,
  interrupted
}

class PrintJobService extends ChangeNotifier {
  final UsbConnectionService connection;
  final GcodeRepository repository;
  final PrintJobStore? store;
  late final Future<void> ready;
  Future<void> _pendingSave = Future.value();
  DateTime? _lastSaved;
  PrintState state = PrintState.idle;
  GcodeMetadata? metadata;
  String? error;
  int currentLayer = 0;
  double progress = 0;
  Duration elapsed = Duration.zero;
  int? remainingMinutes;
  Timer? _timer;
  final _clock = Stopwatch();
  Completer<void>? _resume;
  bool _cancelRequested = false;
  bool _disposed = false;
  Future<void>? _running;

  PrintJobService(this.connection, this.repository, {this.store}) {
    connection.addListener(_connectionChanged);
    ready = _restore();
  }

  Future<void> _restore() async {
    if (store == null) return;
    try {
      final saved = await store!.read();
      if (saved == null || _disposed) return;
      final name = saved['filename'];
      final layers = saved['totalLayers'];
      final time = saved['totalTime'];
      final layer = saved['currentLayer'];
      final percent = saved['progress'];
      final milliseconds = saved['elapsedMilliseconds'];
      final remaining = saved['remainingMinutes'];
      final savedState = saved['state'];
      final savedError = saved['error'];
      if (saved['schema'] != 1 ||
          name is! String ||
          layers is! int ||
          layers < 0 ||
          time is! String ||
          layer is! int ||
          layer < 0 ||
          percent is! num ||
          !percent.isFinite ||
          percent < 0 ||
          percent > 100 ||
          milliseconds is! int ||
          milliseconds < 0 ||
          (remaining != null && (remaining is! int || remaining < 0)) ||
          (savedError != null && savedError is! String) ||
          !PrintState.values.any((value) => value.name == savedState)) {
        throw const FormatException('Invalid print history');
      }
      repository
          .file(name); // Validate the stored basename, without opening it.
      metadata =
          GcodeMetadata(name: name, totalLayers: layers, estimatedTime: time);
      currentLayer = layer;
      progress = percent.toDouble();
      elapsed = Duration(milliseconds: milliseconds);
      remainingMinutes = remaining as int?;
      state = PrintState.values.firstWhere((value) => value.name == savedState);
      if ({
        PrintState.loading,
        PrintState.printing,
        PrintState.paused,
        PrintState.cancelling
      }.contains(state)) {
        state = PrintState.interrupted;
      }
      error = state == PrintState.interrupted
          ? 'Print_interrupted'
          : savedError as String?;
      _notify();
    } catch (_) {
      if (!_disposed) {
        error = 'Print_history_unavailable';
        _notify();
      }
    }
  }

  Future<void> _persist() {
    if (store == null || metadata == null) return Future.value();
    final file = metadata!;
    final snapshot = <String, dynamic>{
      'schema': 1,
      'filename': file.name,
      'totalLayers': file.totalLayers,
      'totalTime': file.estimatedTime,
      'state': state.name,
      'currentLayer': currentLayer,
      'progress': progress,
      'elapsedMilliseconds': elapsed.inMilliseconds,
      'remainingMinutes': remainingMinutes,
      'error': error,
    };
    _lastSaved = DateTime.now();
    // Serialize writes so a slow checkpoint cannot replace a terminal result.
    return _pendingSave =
        _pendingSave.catchError((_) {}).then((_) => store!.write(snapshot));
  }

  Future<void> _persistQuietly() async {
    try {
      await _persist();
    } catch (_) {
      if (!_disposed) {
        error = 'Print_history_unavailable';
        _notify();
      }
    }
  }

  void _connectionChanged() {
    if (isActive && !connection.isConnected) _releasePause();
  }

  bool get isActive =>
      {
        PrintState.loading,
        PrintState.printing,
        PrintState.paused,
        PrintState.cancelling
      }.contains(state) ||
      repository.locked;
  bool get paused => state == PrintState.paused;
  bool get canCancel => {
        PrintState.loading,
        PrintState.printing,
        PrintState.paused,
      }.contains(state);
  String get currentTime => remainingMinutes != null
      ? '${remainingMinutes}m'
      : '${elapsed.inMinutes}:${elapsed.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  Future<void> start(GcodeMetadata file) async {
    await ready;
    if (_disposed || isActive) return;
    metadata = file;
    if (repository.mutationsInProgress) {
      error = 'Printer_busy';
      state = PrintState.failed;
      _notify();
      return;
    }
    if (!connection.isConnected) {
      error = 'USB_is_not_connected';
      state = PrintState.failed;
      _notify();
      return;
    }
    metadata = file;
    error = null;
    currentLayer = 0;
    progress = 0;
    elapsed = Duration.zero;
    remainingMinutes = null;
    _cancelRequested = false;
    state = PrintState.loading;
    repository.locked = connection.printActive = true;
    _notify();
    final run = _run(file);
    _running = run;
    await run;
  }

  Future<void> _run(GcodeMetadata file) async {
    _clock.reset();
    _clock.start();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed = _clock.elapsed;
      if (_lastSaved == null ||
          DateTime.now().difference(_lastSaved!).inSeconds >= 5) {
        _persistQuietly();
      }
      _notify();
    });
    bool hasM73 = false;
    bool sentCommands = false;
    try {
      await repository.ensureReady();
      // Persist an active record before sending any printer command.
      try {
        await _persist();
      } catch (_) {
        throw StateError('Print_history_unavailable');
      }
      if (!_cancelRequested) {
        state = PrintState.printing;
        _notify();
      }
      final lines = repository
          .file(file.name)
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final raw in lines) {
        await _waitIfPaused();
        if (_cancelRequested || _disposed) break;
        final line = raw.trim();
        final command = line.split(';').first.trim();
        if (command.isNotEmpty) {
          sentCommands = true;
          await connection.execute(command, fromPrint: true);
        }
        if (_cancelRequested || _disposed) break;
        final m73 = RegExp(r'^M73\b.*?\bP(\d+)\b', caseSensitive: false)
            .firstMatch(command);
        if (m73 != null) {
          hasM73 = true;
          progress = int.parse(m73.group(1)!).clamp(0, 100).toDouble();
          final remaining = RegExp(r'\bR(\d+)\b').firstMatch(command);
          if (remaining != null) {
            remainingMinutes = int.parse(remaining.group(1)!);
          }
          currentLayer = (file.totalLayers * progress / 100).round();
        } else if (!hasM73) {
          if (line.startsWith(';LAYER_CHANGE')) currentLayer++;
          final layer = RegExp(r'^;LAYER:(\d+)').firstMatch(line);
          if (layer != null) currentLayer = int.parse(layer.group(1)!) + 1;
          if (file.totalLayers > 0) {
            progress = (currentLayer * 100 / file.totalLayers)
                .clamp(0, 100)
                .toDouble();
          }
        }
        _notify();
      }
      await _waitIfPaused();
      if (_disposed) return;
      bool cooled = false;
      if (_cancelRequested) {
        await _cooldown();
        cooled = true;
      }
      // ACK of the last file line only means it was accepted. M400 drains moves.
      await connection.execute('M400', fromPrint: true);
      // Cancellation can be requested while the completion barrier is pending.
      if (_cancelRequested && state != PrintState.cancelling) {
        state = PrintState.cancelling;
      }
      if (_cancelRequested && !cooled) await _cooldown();
      state = _cancelRequested ? PrintState.cancelled : PrintState.completed;
      if (!_cancelRequested) progress = 100;
    } catch (failure) {
      error = failure is StateError &&
              failure.message == 'Print_history_unavailable'
          ? 'Print_history_unavailable'
          : failure.toString();
      state = PrintState.failed;
      if (sentCommands && connection.isConnected && !_disposed) {
        try {
          await _cooldown();
          await connection.execute('M400', fromPrint: true);
        } catch (_) {/* Connection retains the fault. */}
      }
    } finally {
      _timer?.cancel();
      _clock.stop();
      elapsed = _clock.elapsed;
      await _persistQuietly();
      repository.locked = connection.printActive = false;
      _notify();
    }
  }

  Future<void> _cooldown() async {
    for (final command in ['M104 S0', 'M140 S0', 'M106 S0']) {
      await connection.execute(command, fromPrint: true);
    }
  }

  Future<void> _waitIfPaused() async {
    if (!connection.isConnected) throw StateError('USB disconnected');
    if (paused && !_cancelRequested) {
      _resume ??= Completer<void>();
      await _resume!.future;
    }
    if (!connection.isConnected) throw StateError('USB disconnected');
  }

  void pause() {
    if (state != PrintState.printing) return;
    state = PrintState.paused;
    _clock.stop();
    _persistQuietly();
    _notify();
  }

  void resume() {
    if (!paused) return;
    state = PrintState.printing;
    _clock.start();
    _releasePause();
    _persistQuietly();
    _notify();
  }

  Future<void> cancel() async {
    if (!canCancel) return;
    _cancelRequested = true;
    state = PrintState.cancelling;
    _persistQuietly();
    _releasePause();
    _notify();
    await _running;
  }

  void _releasePause() {
    final resume = _resume;
    _resume = null;
    if (resume != null && !resume.isCompleted) resume.complete();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    connection.removeListener(_connectionChanged);
    _cancelRequested = true;
    _timer?.cancel();
    _releasePause();
    super.dispose();
  }
}
