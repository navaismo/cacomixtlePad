import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:CacomixtlePad/services/gcode_repository.dart';
import 'package:CacomixtlePad/services/print_job_service.dart';
import 'support/fake_printer.dart';

void main() {
  late Directory directory;
  late GcodeRepository repository;
  late FakePrinter printer;
  late PrintJobService job;
  const metadata =
      GcodeMetadata(name: 'test.gcode', totalLayers: 2, estimatedTime: '1m');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cacomixtle-test-');
    repository =
        GcodeRepository(directory: directory, requestAccess: () async => true);
    printer = FakePrinter();
    job = PrintJobService(printer, repository);
    await repository
        .file(metadata.name)
        .writeAsString(';LAYER:0\nG1 X10\nG1 X20\n');
  });
  tearDown(() async {
    job.dispose();
    printer.dispose();
    repository.dispose();
    await directory.delete(recursive: true);
  });

  test('last file ACK and M400 barrier are required before completion',
      () async {
    final run = job.start(metadata);
    await until(() => printer.sent.length == 1);
    expect(repository.locked, isTrue);
    printer.respond();
    await until(() => printer.sent.length == 2);
    expect(job.isActive, isTrue);
    printer.respond();
    await until(() => printer.sent.length == 3);
    expect(printer.sent.last, 'M400');
    expect(job.state, PrintState.printing);
    printer.respond();
    await run;
    expect(job.state, PrintState.completed);
    expect(job.progress, 100);
    expect(repository.locked, isFalse);
  });

  test('pause drains in-flight line and resume sends exactly one next line',
      () async {
    final run = job.start(metadata);
    await until(() => printer.sent.length == 1);
    job.pause();
    printer.respond();
    await until(() => printer.sent.length == 2);
    expect(printer.sent.last, 'M400');
    expect(job.state, PrintState.pausing);
    printer.respond();
    await until(() => job.paused);
    expect(job.pauseMessage, 'Pause_parking_unavailable');
    job.resume();
    await until(() => printer.sent.length == 3);
    printer.respond();
    await until(() => printer.sent.length == 4);
    printer.respond();
    await run;
    expect(printer.sent, ['G1 X10', 'M400', 'G1 X20', 'M400']);
  });

  test('cancel stops file transmission and cools without moving the head',
      () async {
    final run = job.start(metadata);
    await until(() => printer.sent.length == 1);
    final cancel = job.cancel();
    expect(job.state, PrintState.cancelling);
    printer.respond();
    for (int i = 2; i <= 5; i++) {
      await until(() => printer.sent.length == i);
      printer.respond();
    }
    await cancel;
    await run;
    expect(job.state, PrintState.cancelled);
    expect(printer.sent, ['G1 X10', 'M104 S0', 'M140 S0', 'M106 S0', 'M400']);
  });

  test('cancel during the final barrier does not report completion', () async {
    final run = job.start(metadata);
    for (int i = 1; i <= 2; i++) {
      await until(() => printer.sent.length == i);
      printer.respond();
    }
    await until(() => printer.sent.length == 3);
    expect(printer.sent.last, 'M400');
    final cancel = job.cancel();
    printer.respond();
    for (int i = 4; i <= 6; i++) {
      await until(() => printer.sent.length == i);
      printer.respond();
    }
    await cancel;
    await run;
    expect(job.state, PrintState.cancelled);
    expect(printer.sent.skip(3), ['M104 S0', 'M140 S0', 'M106 S0']);
  });

  test('pause during the completion barrier cannot report completion early',
      () async {
    final run = job.start(metadata);
    for (var i = 1; i <= 2; i++) {
      await until(() => printer.sent.length == i);
      printer.respond();
    }
    await until(() => printer.sent.length == 3);
    job.pause();
    printer.respond();
    await until(() => printer.sent.length == 4);
    expect(printer.sent.last, 'M400');
    printer.respond();
    await until(() => job.paused);
    expect(job.isActive, isTrue);
    job.resume();
    await run;
    expect(job.state, PrintState.completed);
  });

  test('disconnect while paused fails the job and releases its file lock',
      () async {
    final run = job.start(metadata);
    await until(() => printer.sent.length == 1);
    job.pause();
    printer.respond();
    await Future<void>.delayed(Duration.zero);
    printer.detach();
    await run;
    expect(job.state, PrintState.failed);
    expect(repository.locked, isFalse);
  });

  test('a second start cannot replace the active job', () async {
    final run = job.start(metadata);
    await until(() => printer.sent.isNotEmpty);
    await job.start(const GcodeMetadata(
        name: 'other.gcode', totalLayers: 0, estimatedTime: ''));
    expect(job.metadata!.name, metadata.name);
    printer.detach();
    await run;
  });

  test('temperature ACK is serialized between print lines', () async {
    final run = job.start(metadata);
    await until(() => printer.sent.length == 1);
    final poll = printer.execute('M105');
    printer.respond();
    await until(() => printer.sent.length == 2);
    expect(printer.sent.last, 'M105');
    printer.respond('ok T:200 /200 B:60 /60\n');
    await poll;
    await until(() => printer.sent.length == 3);
    expect(printer.sent.last, 'G1 X20');
    expect(job.isActive, isTrue);
    printer.respond();
    await until(() => printer.sent.length == 4);
    printer.respond();
    await run;
  });

  test('a numbered resend does not skip or complete a print line', () async {
    job.dispose();
    printer.dispose();
    printer = FakePrinter(numbered: true);
    final initialize = printer.protocol.initializeNumbering();
    await until(() => printer.sent.length == 1);
    printer.respond('ok N0\n');
    await initialize;
    job = PrintJobService(printer, repository);
    final run = job.start(metadata);
    await until(() => printer.sent.length == 2);
    printer.respond('Error:checksum mismatch, Last Line: 0\nResend: 1\nok\n');
    await until(() => printer.sent.length == 3);
    expect(printer.sent.last, printer.sent[1]);
    expect(job.state, PrintState.printing);
    printer.respond('ok N1\n');
    await until(() => printer.sent.length == 4);
    expect(printer.sent.last, 'N2 G1 X20*80');
    printer.respond('ok N2\n');
    await until(() => printer.sent.length == 5);
    expect(printer.sent.last, startsWith('N3 M400*'));
    printer.respond('ok N3\n');
    await run;
    expect(job.state, PrintState.completed);
  });
}
