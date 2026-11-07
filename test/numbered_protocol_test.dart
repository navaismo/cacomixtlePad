import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:CacomixtlePad/services/gcode_protocol.dart';
import 'support/fake_printer.dart' show until;

class _Session {
  final input = StreamController<List<int>>(sync: true);
  final writes = <String>[];
  late final GcodeProtocol protocol;
  _Session({int maxRetries = 3}) {
    protocol = GcodeProtocol(
        input: input.stream,
        numbered: true,
        maxRetries: maxRetries,
        write: (bytes) async => writes.add(utf8.decode(bytes).trim()));
  }
  void receive(String value) => input.add(utf8.encode(value));
  Future<void> initialize() async {
    final ready = protocol.initializeNumbering();
    await until(() => writes.isNotEmpty);
    expect(writes, ['N0 M110 N0*125']);
    receive('ok N0\n');
    await ready;
  }

  Future<void> close() async {
    protocol.close();
    await input.close();
  }
}

void main() {
  late _Session session;
  setUp(() => session = _Session());
  tearDown(() => session.close());

  test(
      'initialization is required and numbers include manual temperature queries',
      () async {
    await expectLater(
        session.protocol.send('G1 X10'), throwsA(isA<GcodeException>()));
    await session.initialize();
    final move = session.protocol.send('G1 X10');
    final poll = session.protocol.send('M105');
    await until(() => session.writes.length == 2);
    expect(session.writes.last, 'N1 G1 X10*80');
    session.receive('ok N1 P15 B3\n');
    await move;
    await until(() => session.writes.length == 3);
    expect(session.writes.last, 'N2 M105*37');
    session.receive('ok T:200 /200 B:60 /60\n');
    await poll;
  });

  test(
      'recoverable checksum error retransmits the same bytes without advancing FIFO',
      () async {
    await session.initialize();
    final move = session.protocol.send('G1 X10');
    final next = session.protocol.send('G1 X20');
    bool accepted = false;
    move.then((_) => accepted = true);
    await until(() => session.writes.length == 2);
    session.receive('Error:checksum mismatch, Last Line: 0\nResend: 1\nok\n');
    await until(() => session.writes.length == 3);
    expect(accepted, isFalse);
    expect(session.writes.last, session.writes[1]);
    session.receive('ok N1\n');
    await move;
    await until(() => session.writes.length == 4);
    expect(session.writes.last, 'N2 G1 X20*80');
    session.receive('ok N2\n');
    await next;
  });

  test('fragmented resend trailing ACK is consumed before retry and final ACK',
      () async {
    await session.initialize();
    final move = session.protocol.send('G1 X10');
    bool complete = false;
    move.then((_) => complete = true);
    await until(() => session.writes.length == 2);
    session.receive(
        'Error:Line Number is not Last Line Number+1, Last Line: 0\nRes');
    session.receive('end: 1\no');
    await Future<void>.delayed(Duration.zero);
    expect(session.writes.length, 2);
    session.receive('k\n');
    await until(() => session.writes.length == 3);
    expect(complete, isFalse);
    session.receive('o');
    session.receive('k N1\n');
    await move;
    expect(complete, isTrue);
  });

  test('repeated noise reaches the retry limit and invalidates queued commands',
      () async {
    await session.initialize();
    final first = session.protocol.send('G1 X10');
    final next = session.protocol.send('G1 X20');
    final failures = [
      expectLater(first, throwsA(isA<GcodeException>())),
      expectLater(next, throwsA(isA<GcodeException>()))
    ];
    await until(() => session.writes.length == 2);
    for (int i = 0; i < 3; i++) {
      session.receive('Resend: 1\nok\n');
      await until(() => session.writes.length == 3 + i);
    }
    session.receive('Resend: 1\nok\n');
    await Future.wait(failures);
    expect(session.protocol.isClosed, isTrue);
    expect(session.writes.skip(1).toSet(), {'N1 G1 X10*80'});
  });

  test(
      'does not replay an already acknowledged move when an old number is requested',
      () async {
    await session.initialize();
    final first = session.protocol.send('G1 X10');
    await until(() => session.writes.length == 2);
    session.receive('ok N1\n');
    await first;
    final second = session.protocol.send('G1 X20');
    final failure = expectLater(second, throwsA(isA<GcodeException>()));
    await until(() => session.writes.length == 3);
    session.receive('Resend: 1\nok\n');
    await failure;
    expect(session.writes.length, 3);
  });

  for (final response in ['Error:Heating failed\n', 'ok N42\n']) {
    test('$response is fatal rather than retried', () async {
      await session.initialize();
      final command = session.protocol.send('G1 X10');
      final failure = expectLater(command, throwsA(isA<GcodeException>()));
      await until(() => session.writes.length == 2);
      session.receive(response);
      await failure;
      expect(session.writes.length, 2);
    });
  }

  test('reset while idle invalidates the initialized connection', () async {
    await session.initialize();
    session.receive('start\n');
    expect(session.protocol.isClosed, isTrue);
  });

  test('transport-owned numbering cannot be reset or nested by a G-code file',
      () async {
    await session.initialize();
    for (final command in [
      'M110 N0',
      'M110N0',
      'N50 G1 X10*20',
      'N50G1 X10*20'
    ]) {
      await expectLater(
          session.protocol.send(command), throwsA(isA<GcodeException>()));
    }
    expect(session.writes.length, 1);
  });
}
