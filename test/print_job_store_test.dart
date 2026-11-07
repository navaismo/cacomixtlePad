import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:CacomixtlePad/services/gcode_repository.dart';
import 'package:CacomixtlePad/services/print_job_service.dart';
import 'package:CacomixtlePad/services/print_job_store.dart';
import 'support/fake_printer.dart';

class _MemoryStore implements PrintJobStore {
  Map<String, dynamic>? saved;
  bool failWrites = false;
  Completer<void>? initialGate;
  Completer<void>? terminalGate;
  @override
  Future<Map<String, dynamic>?> read() async => saved;
  @override
  Future<void> write(Map<String, dynamic> value) async {
    if (failWrites) throw StateError('disk full');
    if (value['state'] == 'loading') await initialGate?.future;
    if (value['state'] == 'completed') await terminalGate?.future;
    saved = Map.of(value);
  }
}

void main() {
  late Directory directory;
  late GcodeRepository repository;
  late FakePrinter printer;
  late _MemoryStore store;
  late PrintJobService job;
  const metadata =
      GcodeMetadata(name: 'part.gcode', totalLayers: 2, estimatedTime: '1m');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('print-history-test-');
    repository =
        GcodeRepository(directory: directory, requestAccess: () async => true);
    printer = FakePrinter();
    store = _MemoryStore();
    job = PrintJobService(printer, repository, store: store);
    await repository.file(metadata.name).writeAsString('G1 X10\n');
  });
  tearDown(() async {
    job.dispose();
    printer.dispose();
    repository.dispose();
    await directory.delete(recursive: true);
  });

  test(
      'active record is saved before the first command and terminal record after barrier',
      () async {
    final run = job.start(metadata);
    await until(() => printer.sent.length == 1);
    expect(store.saved!['state'], 'loading');
    expect(store.saved!['filename'], metadata.name);
    printer.respond();
    await until(() => printer.sent.length == 2);
    expect(store.saved!['state'], isNot('completed'));
    printer.respond();
    await run;
    expect(store.saved!['state'], 'completed');
    expect(store.saved!['progress'], 100);
  });

  test(
      'new process restores an active record as interrupted and sends no commands',
      () async {
    final run = job.start(metadata);
    await until(() => printer.sent.length == 1);
    final interruptedStore = _MemoryStore()..saved = Map.of(store.saved!);
    printer.detach();
    await run;
    job.dispose();
    printer.dispose();
    printer = FakePrinter();
    job = PrintJobService(printer, repository, store: interruptedStore);
    await job.ready;
    expect(job.state, PrintState.interrupted);
    expect(job.metadata!.name, metadata.name);
    expect(job.error, 'Print_interrupted');
    expect(job.isActive, isFalse);
    expect(repository.locked, isFalse);
    expect(printer.sent, isEmpty);
  });

  for (final state in ['pausing', 'paused', 'resuming']) {
    test('restoring $state cannot authorize any physical return', () async {
      await job.ready;
      job.dispose();
      store.saved = {
        'schema': 1,
        'filename': metadata.name,
        'state': state,
        'totalLayers': 2,
        'totalTime': '1m',
        'currentLayer': 0,
        'progress': 10,
        'elapsedMilliseconds': 1000,
        'remainingMinutes': null,
        'error': null,
      };
      job = PrintJobService(printer, repository, store: store);
      await job.ready;
      job.resume();
      expect(job.state, PrintState.interrupted);
      expect(printer.sent, isEmpty);
      expect(job.isActive, isFalse);
    });
  }

  test('history write failure refuses to start and releases file lock',
      () async {
    store.failWrites = true;
    await job.start(metadata);
    expect(job.state, PrintState.failed);
    expect(job.error, 'Print_history_unavailable');
    expect(printer.sent, isEmpty);
    expect(repository.locked, isFalse);
  });

  test('cancel before the first file command does not move the head', () async {
    store.initialGate = Completer<void>();
    for (final command in ['G21', 'G90', 'M82', 'G28', 'M84 S120']) {
      printer.motionState.acknowledge(command);
    }
    final run = job.start(metadata);
    await until(() => job.state == PrintState.loading);
    final cancel = job.cancel();
    store.initialGate!.complete();
    for (var i = 1; i <= 4; i++) {
      await until(() => printer.sent.length == i);
      printer.respond();
    }
    await cancel;
    await run;
    expect(job.state, PrintState.cancelled);
    expect(job.error, isNull);
    expect(printer.sent, ['M104 S0', 'M140 S0', 'M106 S0', 'M400']);
  });

  test('cancel preserves the historical record but resets visible progress',
      () async {
    await repository.file(metadata.name).writeAsString('M73 P50 R3\nG1 X10\n');
    final run = job.start(metadata);
    await until(() => printer.sent.length == 1);
    printer.respond();
    await until(() => printer.sent.length == 2);
    expect(job.progress, 50);
    final cancel = job.cancel();
    printer.respond();
    for (var i = 3; i <= 6; i++) {
      await until(() => printer.sent.length == i);
      printer.respond();
    }
    await cancel;
    await run;
    expect(store.saved!['state'], 'cancelled');
    expect(store.saved!['progress'], 50);
    expect(store.saved!['error'], 'Cancel_parking_unavailable');
    expect(job.progress, 0);
    expect(job.currentLayer, 0);
    expect(job.remainingMinutes, isNull);
    expect(job.elapsed, Duration.zero);
    job.dispose();
    job = PrintJobService(printer, repository, store: store);
    await job.ready;
    expect(job.state, PrintState.cancelled);
    expect(job.error, 'Cancel_parking_unavailable');
    expect(job.progress, 0);
    expect(job.currentTime, '0:00');
    expect(job.metadata!.name, metadata.name);
  });

  test('cancel during terminal persistence cannot reopen a completed job',
      () async {
    store.terminalGate = Completer<void>();
    final run = job.start(metadata);
    await until(() => printer.sent.length == 1);
    printer.respond();
    await until(() => printer.sent.length == 2);
    printer.respond();
    await until(() => job.state == PrintState.completed);
    expect(repository.locked, isTrue);
    await job.cancel();
    expect(job.state, PrintState.completed);
    store.terminalGate!.complete();
    await run;
    expect(store.saved!['state'], 'completed');
    expect(job.isActive, isFalse);
  });

  test('corrupt records cannot restore paths or acquire printer locks',
      () async {
    await job.ready;
    job.dispose();
    store.saved = {
      'schema': 1,
      'filename': '../outside.gcode',
      'state': 'printing',
      'totalLayers': 2,
      'totalTime': '1m',
      'currentLayer': 0,
      'progress': 0,
      'elapsedMilliseconds': 0,
      'remainingMinutes': null,
      'error': null,
    };
    job = PrintJobService(printer, repository, store: store);
    await job.ready;
    expect(job.metadata, isNull);
    expect(job.error, 'Print_history_unavailable');
    expect(job.isActive, isFalse);
    expect(printer.sent, isEmpty);
  });

  test('preferences store persists a versioned record and rejects corrupt JSON',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = PreferencesPrintJobStore();
    expect(await preferences.read(), isNull);
    final value = {'schema': 1, 'filename': 'part.gcode', 'state': 'completed'};
    await preferences.write(value);
    expect(await preferences.read(), value);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString(PreferencesPrintJobStore.key)!), value);
    await prefs.setString(PreferencesPrintJobStore.key, '{broken');
    await expectLater(preferences.read(), throwsFormatException);
  });
}
