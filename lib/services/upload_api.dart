import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/form_data.dart';
import 'gcode_repository.dart';

class UploadApi {
  final GcodeRepository repository;
  final String apiKey;
  final int maxRequestBytes;
  UploadApi(this.repository,
      {required this.apiKey, this.maxRequestBytes = 512 * 1024 * 1024});

  Future<Response> call(Request request) async {
    if (request.method == 'GET' && request.url.path == 'api/version') {
      return _json(
          {'api': '0.1', 'server': '1.11.1', 'text': 'OctoPrint 1.11.1'});
    }
    if (request.method == 'GET' && request.url.path == 'api/settings') {
      return _json({
        'accessControl': {
          'autologinHeadsupAcknowledged': false,
          'autologinLocal': false
        },
        'api': {'allowCrossOrigin': false, 'key': null},
      });
    }
    if (request.method != 'POST' ||
        !{'uploads', 'api/files/local'}.contains(request.url.path)) {
      return Response.notFound('Path not found');
    }
    if (apiKey.isEmpty || request.headers['x-api-key'] != apiKey) {
      return Response(401, body: 'API key required');
    }
    if (repository.locked) return Response(409, body: 'Printer busy');
    if ((request.contentLength ?? 0) > maxRequestBytes) {
      return Response(413, body: 'Request too large');
    }
    try {
      int bytes = 0;
      final bounded = request.change(
          body:
              request.read().timeout(const Duration(seconds: 30)).map((chunk) {
        bytes += chunk.length;
        if (bytes > maxRequestBytes) {
          throw StorageException(413, 'File_too_large');
        }
        return chunk;
      }));
      if (!bounded.isMultipartForm) {
        return Response(400, body: 'Expected multipart/form-data');
      }
      int files = 0, parts = 0;
      await for (final form in bounded.multipartFormData) {
        if (++parts > 32) throw StorageException(400, 'Too many form fields');
        if (form.filename != null) {
          await repository.save(form.filename!, form.part);
          files++;
        } else {
          int fieldBytes = 0;
          await for (final chunk in form.part) {
            fieldBytes += chunk.length;
            if (fieldBytes > 65536) {
              throw StorageException(413, 'Form field too large');
            }
          }
        }
      }
      return files == 0
          ? Response(400, body: 'No file supplied')
          : Response.ok('File(s) uploaded successfully');
    } on StorageException catch (error) {
      return Response(error.statusCode, body: error.message);
    } on FormatException {
      return Response(400, body: 'Invalid multipart request');
    } on TimeoutException {
      return Response(408, body: 'Upload timed out');
    } on FileSystemException {
      return Response(500, body: 'Unable to store file');
    }
  }

  Response _json(Map<String, Object?> value) => Response.ok(jsonEncode(value),
      headers: {'Content-Type': 'application/json'});
}
