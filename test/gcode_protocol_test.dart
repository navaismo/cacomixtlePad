import 'dart:async';
import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:CacomixtlePad/services/gcode_protocol.dart';

void main() {
  late StreamController<List<int>> input;
  late List<String> writes;
  late GcodeProtocol protocol;
  setUp(() {
    input = StreamController<List<int>>(sync: true);
    writes = [];
    protocol = GcodeProtocol(
        input: input.stream,
        write: (data) async {
          writes.add(utf8.decode(data).trim());
        });
  });
  tearDown(() async {
    protocol.close();
    await input.close();
  });

  test('fragmented ACK and temperature use a single FIFO', () async {
    final move = protocol.send('G1 X10');
    final temperature = protocol.send('M105');
    await Future<void>.delayed(Duration.zero);
    expect(writes, ['G1 X10']);
    input.add(utf8.encode('o'));
    await Future<void>.delayed(Duration.zero);
    expect(writes.length, 1);
    input.add(utf8.encode('k\r\n'));
    expect(await move, ['ok']);
    await Future<void>.delayed(Duration.zero);
    expect(writes, ['G1 X10', 'M105']);
    input.add(utf8.encode('ok T:200 /200 B:60 /60\n'));
    expect(await temperature, ['ok T:200 /200 B:60 /60']);
  });

  test('two ACKs in one packet cannot confirm an unsent command', () async {
    final first = protocol.send('G28');
    final second = protocol.send('G29');
    bool completed = false;
    second.then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    input.add(utf8.encode('ok\nok\n'));
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(writes, ['G28', 'G29']);
    expect(completed, isFalse);
    input.add(utf8.encode('ok\n'));
    await second;
  });

  test('busy and multiline query responses are retained until ACK', () async {
    final query = protocol.send('M78');
    await Future<void>.delayed(Duration.zero);
    input.add(utf8.encode('echo:busy: processing\nPrints: 12\nFinished: 10\n'));
    expect(protocol.isIdle, isFalse);
    input.add(utf8.encode('Filament used: 20.0m\nok\n'));
    expect(await query, hasLength(5));
  });

  for (final message in ['Error:Heating failed', 'Resend: 2', 'start']) {
    test('$message fails active and queued commands; no later writes',
        () async {
      final active = protocol.send('G1 X10');
      final queued = protocol.send('G1 X20');
      final checks = [
        expectLater(active, throwsA(isA<GcodeException>())),
        expectLater(queued, throwsA(isA<GcodeException>()))
      ];
      await Future<void>.delayed(Duration.zero);
      input.add(utf8.encode('$message\nok\n'));
      await Future.wait(checks);
      expect(protocol.isClosed, isTrue);
      expect(writes, ['G1 X10']);
      await expectLater(
          protocol.send('G1 X30'), throwsA(isA<GcodeException>()));
    });
  }

  test('disconnect fails commands instead of reporting success', () async {
    final sent = protocol.send('G28');
    final result = expectLater(sent, throwsA(isA<GcodeException>()));
    await Future<void>.delayed(Duration.zero);
    await input.close();
    await result;
  });

  test('ACK timeout invalidates the session, busy renews only the idle limit',
      () {
    protocol.close();
    fakeAsync((clock) {
      final source = StreamController<List<int>>(sync: true);
      final p = GcodeProtocol(
          input: source.stream,
          ackTimeout: const Duration(seconds: 2),
          commandTimeout: const Duration(seconds: 5),
          write: (_) async {});
      Object? error;
      p.send('G29').catchError((Object e) {
        error = e;
        return <String>[];
      });
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      source.add(utf8.encode('echo:busy: processing\n'));
      clock.elapse(const Duration(seconds: 1));
      expect(error, isNull);
      clock.elapse(const Duration(seconds: 2));
      clock.flushMicrotasks();
      expect(error, isA<GcodeException>());
      expect(p.isClosed, isTrue);
      source.close();
      clock.flushMicrotasks();
    });
  });

  test('continuous busy reports cannot extend the absolute command deadline',
      () {
    protocol.close();
    fakeAsync((clock) {
      final source = StreamController<List<int>>(sync: true);
      final p = GcodeProtocol(
          input: source.stream,
          ackTimeout: const Duration(seconds: 2),
          commandTimeout: const Duration(seconds: 5),
          write: (_) async {});
      Object? error;
      p.send('G29').catchError((Object e) {
        error = e;
        return <String>[];
      });
      clock.flushMicrotasks();
      for (int i = 0; i < 4; i++) {
        clock.elapse(const Duration(seconds: 1));
        source.add(utf8.encode('echo:busy: processing\n'));
        clock.flushMicrotasks();
        expect(error, isNull);
      }
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(error, isA<GcodeException>());
      source.close();
      clock.flushMicrotasks();
    });
  });

  test('writer failures invalidate active and queued commands', () async {
    protocol.close();
    final failureInput = StreamController<List<int>>();
    bool writerCalled = false;
    protocol = GcodeProtocol(
        input: failureInput.stream,
        write: (_) async {
          writerCalled = true;
          throw StateError('write failed');
        });
    final active = protocol.send('M105');
    final queued = protocol.send('G1 X10');
    await Future.wait([
      expectLater(active, throwsStateError),
      expectLater(queued, throwsStateError),
    ]);
    expect(writerCalled, isTrue);
    expect(protocol.isClosed, isTrue);
    await failureInput.close();
  });
}
