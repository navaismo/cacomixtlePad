import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/print_job_service.dart';
import '../services/gcode_repository.dart';
import '../services/usb_connection_service.dart';
import '../services/temp_svc.dart';
import '../widgets/number_input_dialog.dart';
import '../widgets/responsive_layout.dart';

class PrintJobPage extends StatefulWidget {
  final String filename;
  final String? thumbnailBase64;
  final int totalLayers;
  final String totalTime;
  const PrintJobPage(
      {super.key,
      required this.filename,
      required this.thumbnailBase64,
      required this.totalLayers,
      required this.totalTime});
  @override
  State<PrintJobPage> createState() => _PrintJobPageState();
}

class _PrintJobPageState extends State<PrintJobPage> {
  Future<void> _setValue(
      {required String title,
      required String hint,
      required String command,
      required double maximum,
      double minimum = 0,
      double? initialValue,
      bool integer = false}) async {
    final value = await showNumberInputDialog(context,
        title: title,
        hint: hint,
        maximum: maximum,
        minimum: minimum,
        initialValue: initialValue,
        integer: integer);
    if (value != null && mounted) {
      context
          .read<UsbConnectionService>()
          .sendGCode('$command${integer ? value.toInt() : value}\n', context);
    }
  }

  Future<void> _cancel() async {
    final job = context.read<PrintJobService>();
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              scrollable: true,
              insetPadding: const EdgeInsets.all(12),
              title: Text('Cancel_Print'.tr()),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text('Cancel'.tr())),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text('OK'.tr())),
              ],
            ));
    if (confirmed == true) await job.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final job = context.watch<PrintJobService>();
    final usb = context.watch<UsbConnectionService>();
    final temperature = context.watch<TemperatureService>();
    final selected = job.metadata?.name == widget.filename;
    final printing = selected && job.isActive;
    final paused = selected && job.paused;
    final progress = selected ? job.progress : 0.0;
    final currentLayer = selected ? job.currentLayer : 0;
    final currentTime = selected ? job.currentTime : '0:00';
    final thumbnail = decodeThumbnail(widget.thumbnailBase64);
    final status = selected
        ? {
            PrintState.idle: 'Status_Idle',
            PrintState.loading: 'Status_Loading',
            PrintState.printing: 'Status_Printing',
            PrintState.paused: 'Status_Paused',
            PrintState.cancelling: 'Status_Cancelling',
            PrintState.completed: 'Print_Finished',
            PrintState.cancelled: 'Status_Cancelled',
            PrintState.failed: 'Status_Failed',
            PrintState.interrupted: 'Status_Interrupted',
          }[job.state]!
        : 'Status_Idle';

    return Scaffold(
      appBar:
          AppBar(title: Text(widget.filename, overflow: TextOverflow.ellipsis)),
      body: PageScrollView(
        child: AdaptiveColumns(
          leading: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: progress / 100),
                  duration: const Duration(milliseconds: 500),
                  builder: (context, value, child) => LinearProgressIndicator(
                      value: value.clamp(0.0, 1.0), minHeight: 16),
                ),
                const SizedBox(height: 8),
                Text('${progress.toStringAsFixed(0)}%',
                    style: const TextStyle(
                        fontSize: 24,
                        color: Color.fromARGB(255, 123, 214, 223))),
                if (thumbnail != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Image.memory(thumbnail,
                        height: 140,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image)),
                  ),
                const SizedBox(height: 8),
                Text(widget.filename,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(status.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18,
                        color: Color.fromARGB(179, 130, 236, 164))),
                if (selected && job.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(job.error!.tr(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red)),
                  ),
              ]),
            ),
          ),
          trailing: ControlWrap(minWidth: 135, children: [
            ControlCard(
                icon: Image.asset('assets/icons/hotend_temp.png', height: 32),
                label:
                    '${'Hotend'.tr()}\n${temperature.hotendTemp} / ${temperature.targetHotend.toStringAsFixed(0)}°C',
                onTap: () => _setValue(
                    title: '${'Set'.tr()} ${'Hotend'.tr()} ${'Temp'.tr()}',
                    hint: 'Enter_temperature'.tr(),
                    command: 'M104 S',
                    maximum: 300,
                    initialValue: temperature.targetHotend)),
            ControlCard(
                icon: Image.asset('assets/icons/bed_icon.png', height: 32),
                label:
                    '${'Bed'.tr()}\n${temperature.bedTemp} / ${temperature.targetBed.toStringAsFixed(0)}°C',
                onTap: () => _setValue(
                    title: '${'Set'.tr()} ${'Bed'.tr()} ${'Temp'.tr()}',
                    hint: 'Enter_temperature'.tr(),
                    command: 'M140 S',
                    maximum: 150,
                    initialValue: temperature.targetBed)),
            ControlCard(
                icon: const Icon(Icons.wind_power_rounded, size: 32),
                label: '${'Fan'.tr()} ${temperature.fanSpeed}',
                onTap: () => _setValue(
                    title: 'Set_Fan_Speed'.tr(),
                    hint: 'Enter_fan_speed'.tr(),
                    command: 'M106 S',
                    maximum: 255,
                    initialValue: temperature.fanSpeed.toDouble(),
                    integer: true)),
            ControlCard(
                icon: const Icon(Icons.layers, size: 32),
                label:
                    '${'Layers'.tr()}\n$currentLayer / ${widget.totalLayers}'),
            ControlCard(
                icon: const Icon(Icons.schedule, size: 32),
                label: '${'Time'.tr()}\n$currentTime / ${widget.totalTime}'),
            ControlCard(
                icon: const Icon(Icons.vertical_align_center, size: 32),
                label: 'Z_Offset'.tr(),
                onTap: () => _setValue(
                    title: 'Set_Z_Offset'.tr(),
                    hint: 'ex_string'.tr(),
                    command: 'M851 Z',
                    minimum: -2,
                    maximum: 2)),
            ControlCard(
                icon: const Icon(Icons.play_arrow, size: 32),
                label: 'Start'.tr(),
                enabled: !job.isActive && usb.isConnected,
                onTap: () => job.start(GcodeMetadata(
                    name: widget.filename,
                    totalLayers: widget.totalLayers,
                    estimatedTime: widget.totalTime,
                    thumbnailBase64: widget.thumbnailBase64))),
            ControlCard(
                icon: Icon(paused ? Icons.play_arrow : Icons.pause, size: 32),
                label: (paused ? 'Resume' : 'Pause').tr(),
                enabled:
                    printing && (paused || job.state == PrintState.printing),
                onTap: paused ? job.resume : job.pause),
            ControlCard(
                icon: const Icon(Icons.cancel, size: 32),
                label: 'Stop'.tr(),
                enabled: printing && job.canCancel,
                onTap: _cancel),
          ]),
        ),
      ),
    );
  }
}
