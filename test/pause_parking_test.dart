import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:CacomixtlePad/services/gcode_repository.dart';
import 'package:CacomixtlePad/services/pause_parking.dart';
import 'package:CacomixtlePad/services/print_job_service.dart';
import 'support/fake_printer.dart';

const limitsReport = 'echo:Soft endstops: On Min: X:0.00 Y:0.00 Z:0.00 '
    'Max: X:220.00 Y:220.00 Z:250.00\nok\n';
const originalReport =
    'X:10.00 Y:20.00 Z:5.00 E:100.00 Count X:800 Y:1600 Z:2000\nok\n';
const parkedReport = 'X:10.00 Y:215.00 Z:35.00 E:100.00\nok\n';

PrinterModalState homedModes() {
  final state = PrinterModalState();
  for (final command in ['G21', 'G90', 'M82', 'G28']) {
    state.acknowledge(command);
  }
  return state;
}

void main() {
  test(
      'modes and homing must be known; reset and motor disable invalidate them',
      () {
    final state = PrinterModalState();
    expect(state.canPark, isFalse);
    for (final command in ['G21', 'G90', 'G28 X Y']) {
      state.acknowledge(command);
    }
    expect(state.canPark, isFalse);
    state.acknowledge('G28 Z');
    expect(state.canPark, isTrue);
    state.acknowledge('M83');
    expect(state.relativeExtrusion, isTrue);
    state.acknowledge('G90');
    expect(state.relativeExtrusion, isFalse);
    state.acknowledge('G91');
    expect(state.relativeExtrusion, isTrue);
    state.acknowledge('M82');
    expect(state.relativeExtrusion, isFalse);
    state.acknowledge('M84');
    expect(state.canPark, isFalse);
    state.acknowledge('G28');
    state.reset();
    expect(state.canPark, isFalse);
  });

  test(
      'accept legacy and modern M211 reports; reject disabled or missing bounds',
      () {
    expect(TravelLimits.parse(limitsReport), isNotNull);
    expect(
        TravelLimits.parse(
            limitsReport.replaceFirst('Soft endstops: On', 'M211 S1 ; on')),
        isNotNull);
    expect(TravelLimits.parse(limitsReport.replaceFirst('On', 'Off')), isNull);
    expect(TravelLimits.parse('Unknown command: M211\nok'), isNull);
    expect(TravelLimits.parse(limitsReport.replaceFirst('Max:', '')), isNull);
    expect(FirmwarePosition.parse('ok'), isNull);
    expect(FirmwarePosition.parse(originalReport)!.e, 100);
  });

  test('lift is clamped and rear travel never moves forward', () {
    final limits = TravelLimits.parse(limitsReport)!;
    final snapshot = ParkSnapshot.create(
        homedModes(), const FirmwarePosition(10, 218, 230, 3), limits)!;
    expect(snapshot.parked.z, 250);
    expect(snapshot.parked.y, 218);
    expect(snapshot.limitedLift, isTrue);
    expect(
        ParkSnapshot.create(
            homedModes(), const FirmwarePosition(10, 20, 247, 3), limits),
        isNull);
    expect(
        ParkSnapshot.create(
            homedModes(), const FirmwarePosition(-1, 20, 5, 3), limits),
        isNull);
  });

  group('parking through the real FIFO with simulated firmware', () {
    late Directory directory;
    late GcodeRepository repository;
    late FakePrinter printer;
    late PrintJobService job;
    late int cursor;
    const metadata =
        GcodeMetadata(name: 'part.gcode', totalLayers: 0, estimatedTime: '');
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('pause-test-');
      repository = GcodeRepository(
          directory: directory, requestAccess: () async => true);
      await repository.file(metadata.name).writeAsString('G1 X10\nG1 X20\n');
      printer = FakePrinter();
      for (final command in ['G20', 'G91', 'M83', 'G28', 'M84 S120']) {
        printer.motionState.acknowledge(command);
      }
      job = PrintJobService(printer, repository);
      cursor = 0;
    });
    tearDown(() async {
      job.dispose();
      printer.dispose();
      repository.dispose();
      await directory.delete(recursive: true);
    });

    Future<void> ack(String command, [String response = 'ok\n']) async {
      await until(() => printer.sent.length > cursor);
      expect(printer.sent[cursor++], command);
      printer.respond(response);
    }

    Future<void> preflight() async {
      await until(() => printer.sent.isNotEmpty);
      job.pause();
      expect(job.state, PrintState.pausing);
      job.resume(); // Return must be unavailable until parking has finished.
      expect(job.state, PrintState.pausing);
      await ack('G1 X10');
      await ack('M400');
      await ack('M84 S0');
      await ack('M114', originalReport);
      await ack('M211', limitsReport);
    }

    Future<void> park() async {
      await preflight();
      for (final command in [
        'G21',
        'G90',
        'G0 Z35.000',
        'G0 Y215.000',
        'M400'
      ]) {
        await ack(command);
      }
      await ack('M114', parkedReport);
      await until(() => job.paused);
      expect(printer.pauseMotionActive, isTrue);
      expect(printer.motionState.stepperIdleSeconds, 0);
      expect(printer.motionState.canPark, isTrue);
    }

    test(
        'drains, lifts, parks, restores XY then Z and modes before the next file line',
        () async {
      final run = job.start(metadata);
      await park();
      expect(printer.sent.where((s) => s == 'G1 X20'), isEmpty);
      job.resume();
      expect(job.state, PrintState.resuming);
      await ack('M114', parkedReport);
      await ack('M211', limitsReport);
      await ack('G0 X10.000 Y20.000');
      await ack('G0 Z5.000');
      await ack('M400');
      await ack('M114', originalReport);
      for (final command in [
        'G20',
        'G91',
        'M83',
        'M84 S120.0',
        'G1 X20',
        'M400'
      ]) {
        await ack(command);
      }
      await run;
      expect(job.state, PrintState.completed);
      expect(printer.pauseMotionActive, isFalse);
      expect(printer.motionState.stepperIdleSeconds, 120);
      expect(printer.motionState.millimeters, isFalse);
      expect(printer.motionState.absoluteAxes, isFalse);
      expect(printer.motionState.relativeExtrusion, isTrue);
      expect(
          printer.sent
              .where((s) => s.startsWith('G0'))
              .any((s) => s.contains(' E') || s.contains(' F')),
          isFalse);
      expect(printer.sent.where((s) => s == 'G1 X10'), hasLength(1));
      expect(printer.sent.where((s) => s == 'G1 X20'), hasLength(1));
    });

    test('unsupported limits leave a stationary pause that can resume in place',
        () async {
      final run = job.start(metadata);
      await until(() => printer.sent.isNotEmpty);
      job.pause();
      await ack('G1 X10');
      await ack('M400');
      await ack('M84 S0');
      await ack('M114', originalReport);
      await ack('M211', 'echo:Unknown command: M211\nok\n');
      await until(() => job.paused);
      expect(job.pauseMessage, 'Pause_parking_unavailable');
      job.resume();
      await ack('M84 S120.0');
      await ack('G1 X20');
      await ack('M400');
      await run;
      expect(printer.sent.where((s) => s.startsWith('G0')), isEmpty);
    });

    test('changed parked position fails instead of restoring or printing',
        () async {
      final run = job.start(metadata);
      await park();
      job.resume();
      await ack('M114', 'X:10 Y:210 Z:35 E:100\nok\n');
      await ack('M211', limitsReport);
      for (final command in ['M104 S0', 'M140 S0', 'M106 S0', 'M400']) {
        await ack(command);
      }
      await ack('M84 S120.0');
      await run;
      expect(job.state, PrintState.failed);
      expect(job.error, 'Pause_position_unverified');
      expect(printer.sent, isNot(contains('G1 X20')));
      expect(printer.sent, isNot(contains('G0 X10.000 Y20.000')));
    });

    for (final stage in ['lifting', 'parked', 'returning']) {
      test(
          'cancel while $stage stops at the next ACK without continuing the return',
          () async {
        final run = job.start(metadata);
        if (stage == 'lifting') {
          await preflight();
          await ack('G21');
          await ack('G90');
          await until(() => printer.sent.length > cursor);
          expect(printer.sent[cursor], 'G0 Z35.000');
        } else {
          await park();
          if (stage == 'returning') {
            job.resume();
            await ack('M114', parkedReport);
            await ack('M211', limitsReport);
            await until(() => printer.sent.length > cursor);
            expect(printer.sent[cursor], 'G0 X10.000 Y20.000');
          }
        }
        final cancel = job.cancel();
        if (stage != 'parked') {
          cursor++;
          printer.respond();
        }
        for (final command in ['M104 S0', 'M140 S0', 'M106 S0', 'M400']) {
          await ack(command);
        }
        await ack('M84 S120.0');
        await cancel;
        await run;
        expect(job.state, PrintState.cancelled);
        expect(printer.sent, isNot(contains('G1 X20')));
        expect(printer.sent, isNot(contains('G0 Z5.000')));
      });
    }

    test('disconnect while parked releases the waiter and cannot resume',
        () async {
      final run = job.start(metadata);
      await park();
      printer.detach();
      await run;
      job.resume();
      expect(job.state, PrintState.failed);
      expect(repository.locked, isFalse);
      expect(printer.sent, isNot(contains('G1 X20')));
    });
  });
}
