import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'print_job.dart';
import '../services/print_job_service.dart';
import '../services/gcode_repository.dart';
import '../widgets/gcode_thumbnail.dart';

class PrintPage extends StatefulWidget {
  const PrintPage({
    super.key,
  });

  @override
  State<PrintPage> createState() => _PrintPageState();
}

class _PrintPageState extends State<PrintPage> {
  List<GcodeMetadata> gcodeFiles = [];
  bool _loading = true;
  String? _error;
  late GcodeRepository _repository;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _repository = context.read<GcodeRepository>();
    _repository.addListener(_reload);
    _reload();
  }

  void _reload() {
    _loadGcodeFiles();
  }

  Future<void> _loadGcodeFiles() async {
    final version = ++_loadVersion;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final parsed = await _repository.list();
      if (mounted && version == _loadVersion) {
        setState(() => gcodeFiles = parsed);
      }
    } catch (error) {
      if (mounted && version == _loadVersion) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && version == _loadVersion) setState(() => _loading = false);
    }
  }

  Future<void> _pickAndSaveGcodeFile() async {
    try {
      await _repository.ensureReady();
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null || result.files.single.path == null) return;
      final file = result.files.single;
      await _repository.save(file.name, File(file.path!).openRead());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString().tr())));
      }
    }
  }

  Future<void> _delete(String name) async {
    try {
      await _repository.delete(name);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString().tr())));
      }
    }
  }

  @override
  void dispose() {
    _repository.removeListener(_reload);
    super.dispose();
  }

  void _open(GcodeMetadata file) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PrintJobPage(
                filename: file.name,
                thumbnailBase64: file.thumbnailBase64,
                totalLayers: file.totalLayers,
                totalTime: file.estimatedTime)));
  }

  @override
  Widget build(BuildContext context) {
    final job = context.watch<PrintJobService>();
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return SafeArea(
      child: LayoutBuilder(builder: (context, size) {
        final columns = (size.maxWidth / (190 * scale)).floor().clamp(1, 5);
        return CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverToBoxAdapter(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ElevatedButton(
                          onPressed:
                              job.isActive ? null : _pickAndSaveGcodeFile,
                          child: Text('Upload_G_code'.tr())),
                      IconButton(
                          onPressed: _loading ? null : _loadGcodeFiles,
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Retry'.tr()),
                      if (job.metadata != null)
                        TextButton(
                            onPressed: () => _open(job.metadata!),
                            child: Text(
                                (job.isActive ? 'Active_print' : 'Last_print')
                                    .tr())),
                    ],
                  ),
                  if (job.error != null && job.metadata == null)
                    Text(job.error!.tr()),
                  const SizedBox(height: 12),
                  Text('Select_a_Gcode_file_to_print'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color.fromARGB(255, 137, 234, 198))),
                ],
              )),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()))
            else if (_error != null || gcodeFiles.isEmpty)
              SliverToBoxAdapter(
                  child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text((_error ?? 'No_gcode_files').tr(),
                    textAlign: TextAlign.center),
              ))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: 130 + 140 * scale,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final file = gcodeFiles[index];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: job.isActive && job.metadata?.name != file.name
                            ? null
                            : () => _open(file),
                        child: Stack(children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                    child: GcodeThumbnail(
                                        key: ValueKey(file.name),
                                        base64: file.thumbnailBase64)),
                                const SizedBox(height: 12),
                                Text(file.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text('${'Layers'.tr()}: ${file.totalLayers}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                Text('${'Time'.tr()}: ${file.estimatedTime}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          Positioned(
                              top: 0,
                              right: 0,
                              child: IconButton(
                                icon: const Icon(Icons.delete, size: 22),
                                tooltip: 'Delete',
                                onPressed: job.isActive
                                    ? null
                                    : () => _delete(file.name),
                              )),
                        ]),
                      ),
                    );
                  }, childCount: gcodeFiles.length),
                ),
              ),
          ],
        );
      }),
    );
  }
}
