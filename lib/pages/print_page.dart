// Flutter printer ui/lib/pages/print page.dart
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:CacomixtlePad/pages/print_job.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/usbConn_svc.dart';

class GcodeMetadata {
  final String name;
  final int totalLayers;
  final String estimatedTime;
  final String? thumbnailBase64;

  GcodeMetadata({
    required this.name,
    required this.totalLayers,
    required this.estimatedTime,
    this.thumbnailBase64,
  });
}

class PrintPage extends StatefulWidget {
  const PrintPage({
    super.key,
  });

  @override
  State<PrintPage> createState() => _PrintPageState();
}

class _PrintPageState extends State<PrintPage> {
  List<GcodeMetadata> gcodeFiles = [];
  HttpServer? _server;
  String? localIp;

  @override
  void initState() {
    super.initState();
    _ensureGcodeFolder().then((_) {
      _loadGcodeFiles();
    });
  }

  Future<String> _getExternalGcodeDirectory() async {
    final dir = Directory('/storage/emulated/0/Download/gcode_files');
    if (!(await dir.exists())) await dir.create(recursive: true);
    return dir.path;
  }

  Future<void> _ensureGcodeFolder() async {
    if (!await Permission.manageExternalStorage.request().isGranted) {
      print("Permission_denied".tr());
    } else {
      await _getExternalGcodeDirectory();
    }
  }

  Future<GcodeMetadata> _parseGcodeFile(String filePath) async {
  final lines = await File(filePath).readAsLines();
  int totalLayers = 0;
  String estimatedTime = '';
  String? bestThumbnail;
  int bestArea = 0;

  bool inThumbnailBlock = false;
  int currentW = 0, currentH = 0;
  final buffer = StringBuffer();

  for (var raw in lines) {
    final line = raw.trim();

    
    if (line.toLowerCase().startsWith('; total layer number:') ||
        line.toLowerCase().startsWith(';layer_count:')) {
      totalLayers = int.tryParse(line.split(':').last.trim()) ?? totalLayers;
      continue;
    }

    
    if (line.toLowerCase().startsWith('; estimated printing time')) {
      final parts = line.split('=');
      if (parts.length > 1) estimatedTime = parts[1].trim();
      continue;
    } else if (line.toLowerCase().startsWith(';time:')) {
      final seconds = int.tryParse(line.split(':').last.trim()) ?? 0;
      final duration = Duration(seconds: seconds);
      estimatedTime = [
        if (duration.inHours > 0) '${duration.inHours}h',
        if (duration.inMinutes.remainder(60) > 0) '${duration.inMinutes.remainder(60)}m',
        if (duration.inSeconds.remainder(60) > 0) '${duration.inSeconds.remainder(60)}s',
      ].join(' ');
      continue;
    }

    
    if (line.toLowerCase().startsWith('; thumbnail begin')) {
      inThumbnailBlock = true;
      currentW = 0;
      currentH = 0;
      buffer.clear();

      final match = RegExp(r';\s*thumbnail\s+begin\s+(\d+)x(\d+)', caseSensitive: false).firstMatch(line);
      if (match != null) {
        currentW = int.parse(match.group(1)!);
        currentH = int.parse(match.group(2)!);
      }
      continue;
    }

    if (inThumbnailBlock) {
      if (line.toLowerCase().startsWith('; thumbnail end')) {
        final area = currentW * currentH;
        if (area > bestArea && buffer.isNotEmpty) {
          bestArea = area;
          bestThumbnail = buffer.toString().replaceAll('\n', '').replaceAll('; ', '');
        }
        inThumbnailBlock = false;
        continue;
      }

      if (line.startsWith(';')) {
        buffer.write(line.substring(1).trim());
      }
      continue;
    }
  }

  return GcodeMetadata(
    name: path.basename(filePath),
    totalLayers: totalLayers,
    estimatedTime: estimatedTime,
    thumbnailBase64: bestThumbnail,
  );
}

  

  Future<void> _loadGcodeFiles() async {
    try {
      final dirPath = await _getExternalGcodeDirectory();
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        setState(() => gcodeFiles = []);
        return;
      }

      final files = dir
          .listSync()
          .where((f) => f.path.toLowerCase().endsWith(".gcode"))
          .cast<File>();

      final parsed =
          await Future.wait(files.map((file) => _parseGcodeFile(file.path)));
      setState(() => gcodeFiles = parsed);
    } catch (e) {
      print('Error_loading_Gcode_files'.tr() + ' $e');
      setState(() => gcodeFiles = []);
    }
  }

  Future<void> _pickAndSaveGcodeFile() async {
    if (!await Permission.manageExternalStorage.request().isGranted) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      if (!file.name.toLowerCase().endsWith('.gcode')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Only_gcode_files_are_allowed'.tr())),
        );
        return;
      }
      final selected = File(file.path!);
      final destination =
          File(path.join(await _getExternalGcodeDirectory(), file.name));
      await selected.copy(destination.path);
      _loadGcodeFiles();
    }
  }

  @override
  void dispose() {
    _server?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usbService = Provider.of<UsbConnectionService>(context);
    final screenWidth = MediaQuery.of(context).size.width;

    int crossAxisCount;
    if (screenWidth >= 1400) {
      crossAxisCount = 5;
    } else if (screenWidth >= 1000) {
      crossAxisCount = 4;
    } else if (screenWidth >= 700) {
      crossAxisCount = 3;
    } else {
      crossAxisCount = 2;
    }

    final thumbnailSize = screenWidth / (crossAxisCount * 2.5);

    if (gcodeFiles.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton(
            onPressed: usbService.port == null ? null : _pickAndSaveGcodeFile,
            child: Text(
              usbService.port == null
                  ? 'Connect_to_the_Printer'.tr()
                  : 'Upload_G_code'.tr(),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Select_a_Gcode_file_to_print'.tr(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 137, 234, 198),
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 1.3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: gcodeFiles.length,
              itemBuilder: (context, index) {
                final file = gcodeFiles[index];
                return GestureDetector(
                  onTap: () {
                    if (usbService.port == null && !kDebugMode) {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('Error'.tr()),
                          content: Text('Please_connect_to_a_port_first'.tr()),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text('OK'.tr()),
                            ),
                          ],
                        ),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PrintJobPage(
                            filename: file.name,
                            thumbnailBase64: file.thumbnailBase64,
                            totalLayers: file.totalLayers,
                            totalTime: file.estimatedTime,
                          ),
                        ),
                      );
                    }
                  },
                  child: Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      children: [
                        Center( // <-- Wrap Padding with Center to center its child
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center, // Center vertically
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                file.thumbnailBase64 != null
                                    ? Image.memory(
                                        base64Decode(file.thumbnailBase64!),
                                        width: thumbnailSize,
                                        height: thumbnailSize,
                                        fit: BoxFit.cover,
                                      )
                                    : Icon(Icons.insert_drive_file, size: thumbnailSize),
                                const SizedBox(height: 10),
                                Text(
                                  file.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Color.fromARGB(255, 142, 96, 227),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text('Layers'.tr() + ': ${file.totalLayers}',
                                    style: const TextStyle(fontSize: 13)),
                                Text('Time'.tr() + ': ${file.estimatedTime}',
                                    style: const TextStyle(fontSize: 13)),
                                const Spacer(),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          child: IconButton(
                            icon: const Icon(Icons.delete,
                                color: Color.fromARGB(255, 252, 252, 252), size: 22),
                            tooltip: 'Delete',
                            onPressed: () async {
                              final dirPath = await _getExternalGcodeDirectory();
                              final filePath = path.join(dirPath, file.name);
                              final gcodeFile = File(filePath);
                              if (await gcodeFile.exists()) {
                                await gcodeFile.delete();
                                _loadGcodeFiles();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
