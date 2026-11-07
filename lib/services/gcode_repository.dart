import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';

class GcodeMetadata {
  final String name;
  final int totalLayers;
  final String estimatedTime;
  final String? thumbnailBase64;
  const GcodeMetadata(
      {required this.name,
      required this.totalLayers,
      required this.estimatedTime,
      this.thumbnailBase64});
}

Uint8List? decodeThumbnail(String? value) {
  if (value == null || value.length > 4 * 1024 * 1024) return null;
  try {
    return base64Decode(value);
  } on FormatException {
    return null;
  }
}

class StorageException implements Exception {
  final int statusCode;
  final String message;
  StorageException(this.statusCode, this.message);
  @override
  String toString() => message;
}

Future<bool> requestStorageAccess() async {
  if (!Platform.isAndroid) return true;
  const channel = MethodChannel('com.shaka.cacomixtlePad/platform');
  final sdk = await channel.invokeMethod<int>('sdkVersion');
  final permission =
      (sdk ?? 30) >= 30 ? Permission.manageExternalStorage : Permission.storage;
  return await permission.isGranted || await permission.request().isGranted;
}

class GcodeRepository extends ChangeNotifier {
  final Directory directory;
  final Future<bool> Function() requestAccess;
  final int maxFileBytes;
  final _pendingNames = <String>{};
  bool locked = false;
  bool _disposed = false;
  Future<void>? _preparing;

  GcodeRepository(
      {Directory? directory,
      Future<bool> Function()? requestAccess,
      this.maxFileBytes = 256 * 1024 * 1024})
      : directory =
            directory ?? Directory('/storage/emulated/0/Download/gcode_files'),
        requestAccess = requestAccess ?? requestStorageAccess;

  bool get mutationsInProgress => _pendingNames.isNotEmpty;

  Future<void> ensureReady() => _preparing ??= _prepare();
  Future<void> _prepare() async {
    try {
      if (!await requestAccess()) {
        throw StorageException(403, 'Permission_denied');
      }
      await directory.create(recursive: true);
    } catch (_) {
      rethrow;
    } finally {
      // Coalesce concurrent permission prompts, but recheck on later operations
      // (Android can revoke storage access while the app remains installed).
      _preparing = null;
    }
  }

  File file(String name) {
    if (name.isEmpty ||
        name.length > 180 ||
        name.startsWith('.') ||
        name.contains(RegExp(r'[/\\:\x00-\x1f\x7f]')) ||
        !name.toLowerCase().endsWith('.gcode') ||
        path.basename(name) != name) {
      throw StorageException(400, 'Only_gcode_files_are_allowed');
    }
    return File(path.join(directory.path, name));
  }

  void _checkWritable() {
    if (locked) throw StorageException(409, 'Printer_busy');
  }

  Future<void> save(String name, Stream<List<int>> data) async {
    _checkWritable();
    final target = file(name);
    if (!_pendingNames.add(name)) throw StorageException(409, 'File_exists');
    Directory? temporary;
    IOSink? sink;
    try {
      await ensureReady();
      if (await FileSystemEntity.type(target.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StorageException(409, 'File_exists');
      }
      temporary = await directory.createTemp('.upload-');
      final staging = File(path.join(temporary.path, 'data'));
      sink = staging.openWrite();
      // Observe sink errors immediately, including failures before close().
      final sinkDone = sink.done;
      sinkDone.ignore();
      int count = 0;
      await for (final chunk in data) {
        _checkWritable();
        count += chunk.length;
        if (count > maxFileBytes) throw StorageException(413, 'File_too_large');
        sink.add(chunk);
        await sink.flush();
      }
      await sink.close();
      sink = null;
      if (count == 0) throw StorageException(400, 'Empty_file');
      _checkWritable();
      if (await FileSystemEntity.type(target.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StorageException(409, 'File_exists');
      }
      await staging.rename(target.path);
      if (!_disposed) notifyListeners();
    } finally {
      try {
        await sink?.close();
      } catch (_) {/* Preserve the original error. */}
      if (temporary != null && await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
      _pendingNames.remove(name);
    }
  }

  Future<void> delete(String name) async {
    _checkWritable();
    if (!_pendingNames.add(name)) throw StorageException(409, 'Printer_busy');
    try {
      await file(name).delete();
      if (!_disposed) notifyListeners();
    } finally {
      _pendingNames.remove(name);
    }
  }

  Future<List<GcodeMetadata>> list() async {
    await ensureReady();
    final result = <GcodeMetadata>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File || !entry.path.toLowerCase().endsWith('.gcode')) {
        continue;
      }
      result.add(await parse(entry));
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  static Future<GcodeMetadata> parse(File source) async {
    int totalLayers = 0, bestArea = 0, area = 0;
    String estimatedTime = '';
    String? thumbnail;
    StringBuffer? buffer;
    await for (final raw in source
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final line = raw.trim();
      final lower = line.toLowerCase();
      if (lower.startsWith('; total layer number:') ||
          lower.startsWith(';layer_count:')) {
        totalLayers = int.tryParse(line.split(':').last.trim()) ?? totalLayers;
      } else if (lower.startsWith('; estimated printing time')) {
        final split = line.indexOf('=');
        if (split >= 0) estimatedTime = line.substring(split + 1).trim();
      } else if (lower.startsWith(';time:')) {
        final seconds = int.tryParse(line.split(':').last.trim()) ?? 0;
        final d = Duration(seconds: seconds);
        estimatedTime =
            '${d.inHours}h ${d.inMinutes.remainder(60)}m ${d.inSeconds.remainder(60)}s';
      } else if (lower.startsWith('; thumbnail begin')) {
        final size = RegExp(r'(\d+)x(\d+)').firstMatch(line);
        area = size == null
            ? 0
            : int.parse(size.group(1)!) * int.parse(size.group(2)!);
        buffer = StringBuffer();
      } else if (lower.startsWith('; thumbnail end')) {
        if (buffer != null &&
            area > bestArea &&
            decodeThumbnail(buffer.toString()) != null) {
          thumbnail = buffer.toString();
          bestArea = area;
        }
        buffer = null;
      } else if (buffer != null && line.startsWith(';')) {
        buffer.write(line.substring(1).trim());
        if (buffer.length > 4 * 1024 * 1024) buffer = null;
      }
    }
    return GcodeMetadata(
        name: path.basename(source.path),
        totalLayers: totalLayers,
        estimatedTime: estimatedTime,
        thumbnailBase64: thumbnail);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
