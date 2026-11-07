// Audit reproductions: these assertions document the vulnerable behavior.
// Run with: flutter test tool/security_audit_poc.dart --no-pub --reporter expanded
// All files are temporary; all printer commands use a simulated transport.
import 'dart:convert';
import 'dart:io';

import 'package:CacomixtlePad/services/gcode_repository.dart';
import 'package:CacomixtlePad/services/print_job_service.dart';
import 'package:CacomixtlePad/services/upload_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_multipart/form_data.dart';
import 'package:shelf_multipart/multipart.dart';

import '../test/support/fake_printer.dart';

Future<void> waitFor(bool Function() condition) async {
  for (var i = 0; i < 1000; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  throw StateError('Audit reproduction timed out');
}

Request upload(String name, List<int> contents) => Request(
      'POST',
      Uri.parse('http://localhost/uploads'),
      headers: {
        'content-type': 'multipart/form-data; boundary=audit',
        'x-api-key': 'audit-key-not-a-real-credential',
      },
      body: <int>[
        ...utf8.encode('--audit\r\nContent-Disposition: form-data; '
            'name="file"; filename="$name"\r\n\r\n'),
        ...contents,
        ...utf8.encode('\r\n--audit--\r\n'),
      ],
    );

void main() {
  late Directory temporary;
  late GcodeRepository repository;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('cacomixtle-audit-');
    repository = GcodeRepository(
      directory: Directory(path.join(temporary.path, 'library')),
      requestAccess: () async => true,
    );
    await repository.ensureReady();
  });

  tearDown(() async {
    repository.dispose();
    await temporary.delete(recursive: true);
  });

  test('HTTP exposes the reusable API credential to the transport', () async {
    String? observedKey;
    final api =
        UploadApi(repository, apiKey: 'audit-key-not-a-real-credential');
    final server = await shelf_io.serve((request) {
      observedKey = request.headers['x-api-key'];
      return api.call(request);
    }, InternetAddress.loopbackIPv4, 0);
    final socket =
        await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    try {
      const body = '--audit\r\nContent-Disposition: form-data; '
          'name="file"; filename="transport.gcode"\r\n\r\n'
          'M117 AUDIT\r\n--audit--\r\n';
      socket.write('POST /uploads HTTP/1.1\r\n'
          'Host: localhost\r\n'
          'Connection: close\r\n'
          'X-Api-Key: audit-key-not-a-real-credential\r\n'
          'Content-Type: multipart/form-data; boundary=audit\r\n'
          'Content-Length: ${utf8.encode(body).length}\r\n\r\n$body');
      await socket.flush();
      final response = await utf8.decoder.bind(socket).join();
      expect(response, contains('200 OK'));
      expect(observedKey, 'audit-key-not-a-real-credential');
    } finally {
      socket.destroy();
      await server.close(force: true);
    }
  });

  test('a file changed after preview is printed without an integrity check',
      () async {
    final source = repository.file('reviewed.gcode');
    await source.writeAsString(';LAYER_COUNT:1\nM117 ORIGINAL\n');
    final preview = (await repository.list()).single;
    await source.writeAsString(';LAYER_COUNT:1\nM117 MODIFIED\n');
    final printer = FakePrinter();
    final job = PrintJobService(printer, repository);
    try {
      final run = job.start(preview);
      await waitFor(() => printer.sent.isNotEmpty);
      expect(printer.sent.first, 'M117 MODIFIED');
      printer.respond();
      await waitFor(() => printer.sent.length == 2);
      printer.respond();
      await run;
      expect(job.state, PrintState.completed);
    } finally {
      job.dispose();
      printer.dispose();
    }
  });

  test('the repository lock does not prevent changing a running print file',
      () async {
    final source = repository.file('running.gcode');
    final prefix = 'G4 P1\n${';${'A' * 1022}\n' * 512}';
    await source.writeAsString('${prefix}M117 ORIGINAL\n');
    final printer = FakePrinter();
    final job = PrintJobService(printer, repository);
    try {
      final run = job.start(const GcodeMetadata(
          name: 'running.gcode', totalLayers: 1, estimatedTime: ''));
      await waitFor(() => printer.sent.length == 1);
      expect(repository.locked, isTrue);
      final writer = await source.open(mode: FileMode.writeOnlyAppend);
      await writer.setPosition(utf8.encode(prefix).length);
      await writer.writeString('M117 MODIFIED\n');
      await writer.close();
      printer.respond();
      await waitFor(() => printer.sent.length == 2);
      expect(printer.sent[1], 'M117 MODIFIED');
      printer.respond();
      await waitFor(() => printer.sent.length == 3);
      printer.respond();
      await run;
      expect(job.state, PrintState.completed);
    } finally {
      job.dispose();
      printer.dispose();
    }
  });

  test('an accepted invalid UTF-8 upload prevents listing the whole library',
      () async {
    final api =
        UploadApi(repository, apiKey: 'audit-key-not-a-real-credential');
    expect(
        (await api.call(upload('valid.gcode', utf8.encode('M117 OK\n'))))
            .statusCode,
        200);
    expect(
        (await api.call(upload('poison.gcode', [0xff, 0xfe, 0x0a]))).statusCode,
        200);
    await expectLater(repository.list(), throwsFormatException);
    await repository.delete('poison.gcode');
    expect((await repository.list()).single.name, 'valid.gcode');
  });

  test('per-file limits do not impose a total storage quota', () async {
    final small = GcodeRepository(
        directory: repository.directory,
        requestAccess: () async => true,
        maxFileBytes: 16);
    try {
      final api = UploadApi(small,
          apiKey: 'audit-key-not-a-real-credential', maxRequestBytes: 1024);
      for (var i = 0; i < 10; i++) {
        expect(
            (await api.call(
                    upload('quota-$i.gcode', utf8.encode('M117 AUDIT\n'))))
                .statusCode,
            200);
      }
      var total = 0;
      await for (final file in small.directory.list()) {
        total += (await file.stat()).size;
      }
      expect(total, greaterThan(small.maxFileBytes));
    } finally {
      small.dispose();
    }
  });

  test('the baseline upload handler allows unauthenticated path traversal',
      () async {
    // This reproduces the upload branch of 9f7a9e1:lib/main.dart, with its
    // Android directory replaced by an isolated temporary directory.
    Future<Response> baselineHandler(Request request) async {
      if (request.isMultipart && request.isMultipartForm) {
        final forms = await request.multipartFormData.toList();
        for (final form in forms) {
          final name = form.filename;
          if (name != null) {
            final target = File(path.join(repository.directory.path, name));
            final sink = target.openWrite();
            await form.part.pipe(sink);
            await sink.close();
          }
        }
      }
      return Response.ok('File(s) uploaded successfully');
    }

    final request = upload('../outside.gcode', utf8.encode('M117 AUDIT\n'));
    final unauthenticated = request.change(headers: {'x-api-key': null});
    final response = await baselineHandler(unauthenticated)
        .timeout(const Duration(seconds: 2));
    expect(response.statusCode, 200);
    expect(
        await File(path.join(temporary.path, 'outside.gcode')).readAsString(),
        'M117 AUDIT\n');
  });
}
