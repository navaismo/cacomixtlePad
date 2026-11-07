import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:CacomixtlePad/services/gcode_repository.dart';
import 'package:CacomixtlePad/services/usb_connection_service.dart';
import 'package:CacomixtlePad/services/upload_api.dart';
import 'package:shelf/shelf.dart';

void main() {
  late Directory directory;
  late GcodeRepository repository;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gcode-storage-test-');
    repository = GcodeRepository(
        directory: directory,
        requestAccess: () async => true,
        maxFileBytes: 100);
  });
  tearDown(() async {
    repository.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> save(String name, String text) =>
      repository.save(name, Stream.value(utf8.encode(text)));
  Request upload(String name,
          {String? key = 'secret', String text = 'G28', String? route}) =>
      Request('POST', Uri.parse('http://localhost/${route ?? 'uploads'}'),
          headers: {
            'content-type': 'multipart/form-data; boundary=abc',
            if (key != null) 'x-api-key': key
          },
          body:
              '--abc\r\nContent-Disposition: form-data; name="file"; filename="$name"\r\n\r\n$text\r\n--abc--\r\n');

  test('traversal, absolute paths and unsupported extensions are rejected',
      () async {
    for (final name in [
      '../escape.gcode',
      '/tmp/escape.gcode',
      'x\\escape.gcode',
      'x.txt',
      '.hidden.gcode'
    ]) {
      await expectLater(save(name, 'G28'), throwsA(isA<StorageException>()));
    }
    expect(await directory.list().toList(), isEmpty);
  });
  test('duplicate names do not overwrite existing G-code', () async {
    await save('part.gcode', 'G28');
    await expectLater(
        save('part.gcode', 'G29'), throwsA(isA<StorageException>()));
    expect(await repository.file('part.gcode').readAsString(), 'G28');
  });
  test('oversized and interrupted uploads leave no visible or partial files',
      () async {
    await expectLater(
        save('large.gcode', 'X' * 101), throwsA(isA<StorageException>()));
    final stream = Stream<List<int>>.multi((controller) {
      controller.add(utf8.encode('G28'));
      controller.addError(const FormatException('broken stream'));
      controller.close();
    });
    await expectLater(
        repository.save('broken.gcode', stream), throwsFormatException);
    expect(await directory.list().toList(), isEmpty);
    expect(repository.mutationsInProgress, isFalse);
  });
  test('active job blocks upload and delete', () async {
    await save('part.gcode', 'G28');
    repository.locked = true;
    await expectLater(
        save('other.gcode', 'G29'), throwsA(isA<StorageException>()));
    await expectLater(
        repository.delete('part.gcode'), throwsA(isA<StorageException>()));
    expect(await repository.file('part.gcode').readAsString(), 'G28');
  });
  test('API requires a key and rejects invalid names and collisions', () async {
    final api = UploadApi(repository, apiKey: 'secret');
    expect((await api.call(upload('part.gcode', key: null))).statusCode, 401);
    expect(
        (await api.call(upload('part.gcode', key: 'wrong'))).statusCode, 401);
    expect((await api.call(upload('../escape.gcode'))).statusCode, 400);
    expect((await api.call(upload('part.gcode'))).statusCode, 200);
    expect((await api.call(upload('part.gcode'))).statusCode, 409);
    expect(
        (await api.call(upload('orca.gcode', route: 'api/files/local')))
            .statusCode,
        200);
    repository.locked = true;
    expect((await api.call(upload('blocked.gcode'))).statusCode, 409);
  });
  test('API limits streaming uploads without Content-Length', () async {
    final api = UploadApi(repository, apiKey: 'secret', maxRequestBytes: 80);
    final request = upload('large.gcode', text: 'X' * 80);
    expect((await api.call(request)).statusCode, 413);
    expect(await directory.list().toList(), isEmpty);
  });
  test('malformed multipart and absent file return 400; discovery stays public',
      () async {
    final api = UploadApi(repository, apiKey: 'secret');
    final bad = Request('POST', Uri.parse('http://localhost/uploads'),
        headers: {'x-api-key': 'secret', 'content-type': 'text/plain'},
        body: 'G28');
    expect((await api.call(bad)).statusCode, 400);
    expect(
        (await api.call(
                Request('GET', Uri.parse('http://localhost/api/version'))))
            .statusCode,
        200);
  });
  test('permission denial can be retried', () async {
    bool granted = false;
    final denied = GcodeRepository(
        directory: directory, requestAccess: () async => granted);
    await expectLater(denied.ensureReady(), throwsA(isA<StorageException>()));
    granted = true;
    await denied.ensureReady();
    denied.dispose();
  });
  test('metadata parser supports Cura and ignores malformed Base64', () async {
    final source = repository.file('cura.gcode');
    await source.writeAsString(
        ';LAYER_COUNT:2\n;TIME:65\n; thumbnail begin 100x100\n; invalid!\n; thumbnail end\nG28\n');
    final metadata = await GcodeRepository.parse(source);
    expect(metadata.totalLayers, 2);
    expect(metadata.estimatedTime, '0h 1m 5s');
    expect(metadata.thumbnailBase64, isNull);
    expect(decodeThumbnail('!'), isNull);
  });
  test('bilinear mesh works without subdivision and skips column labels', () {
    final grid = UsbConnectionService.parseBedGrid(
        'Bilinear Leveling Grid:\n 0 1\n0 +0.10 -0.20\n1 -0.30 +0.40\nok\n');
    expect(grid.length, 4);
    expect(grid[GridPoint(0, 0)], 0.1);
    expect(grid[GridPoint(1, 1)], 0.4);
    expect(
        UsbConnectionService.parseBedGrid(
            'Bilinear Leveling Grid:\n 0 1\n0 +0.10 -0.20\n'),
        isEmpty);
  });
}
