// Flutter printer ui/lib/pages/print job.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:path/path.dart' as path;
import '../services/temp_svc.dart';
import '../services/usbConn_svc.dart';
import 'package:provider/provider.dart';

class PrintJobPage extends StatefulWidget {
  final String filename;
  final String? thumbnailBase64;
  final int totalLayers;
  final String totalTime;

  const PrintJobPage({
    super.key,
    required this.filename,
    required this.thumbnailBase64,
    required this.totalLayers,
    required this.totalTime,
  });

  @override
  State<PrintJobPage> createState() => _PrintJobPageState();
}

class _PrintJobPageState extends State<PrintJobPage> {
  int currentLayer = 0;
  String currentTime = "0:00";
  bool printing = false;
  bool paused = false;
  List<String> gcodeLines = [];
  int currentLineIndex = 0;
  StreamSubscription? _serialSub;
  bool waitingForOk = false;
  DateTime? _startTime;
  Timer? _timer;
  bool hasM73 = false;
  int m73Progress = 0;
  Uint8List? decodedThumbnail;
  double progress = 0.0;

  @override
  void dispose() {
    _serialSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.thumbnailBase64 != null) {
      decodedThumbnail = base64Decode(widget.thumbnailBase64!);
    }
  }

  void _showTempInputDialog(
      String label, String currentValue, void Function(double) onSubmit) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Set'.tr() + ' ' + label + ' ' + 'Temp'.tr()),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: "Enter_temperature".tr()),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              if (value != null) {
                onSubmit(value);
              }
              Navigator.pop(context);
            },
            child: Text('OK'.tr()),
          ),
        ],
      ),
    );
  }

  bool _containsM73(List<String> lines) {
    for (var line in lines) {
      if (RegExp(r'M73\s+P\d+\s+R\d+').hasMatch(line)) {
        return true;
      }
    }
    return false;
  }

  void startPrintJob(UsbConnectionService usbService, BuildContext context) async {
    if (usbService.port == null && !kDebugMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please_connect_to_a_port_first'.tr())),
      );
      return;
    }

    final filePath =
        path.join('/storage/emulated/0/Download/gcode_files', widget.filename);
    final file = File(filePath);
    if (!await file.exists()) return;

    gcodeLines = await file.readAsLines();
    hasM73 = _containsM73(gcodeLines);
    currentLineIndex = 0;
    printing = true;
    paused = false;
    setState(() {});

    if (kDebugMode) {
      _sendNextLine(usbService, context);
    } else {
      _serialSub = usbService.port!.inputStream!.listen((data) {
        final response = String.fromCharCodes(data);
        if (response.contains('ok')) {
          waitingForOk = false;
          _sendNextLine(usbService, context);
        } else if (response.contains('busy')) {
          waitingForOk = true;
        }
      });

      _sendNextLine(usbService, context);
    }
  }

  void _sendNextLine(
      UsbConnectionService usbService, BuildContext context) async {
    if (!printing || paused || waitingForOk) return;

    while (currentLineIndex < gcodeLines.length) {
      final line = gcodeLines[currentLineIndex++].trim();

      if (hasM73) {
        final m73 = RegExp(r'M73\s+P(\d+)\s+R(\d+)').firstMatch(line);
        if (m73 != null) {
          final p = int.parse(m73.group(1)!);
          final rMin = int.parse(m73.group(2)!);
          setState(() {
            progress = p.toDouble();
            currentTime = '${rMin}m';
            currentLayer = ((widget.totalLayers * p) / 100).round();
          });
        }
      } else {
        // ORCA/CURA alternative way
        if (line.contains(';LAYER_CHANGE')) {
          setState(() {
            currentLayer++;
          });
          
        }

        final curaMatch = RegExp(r';LAYER:(\d+)').firstMatch(line);
        if (curaMatch != null) {
          final layer = int.tryParse(curaMatch.group(1)!);
          if (layer != null) {
            setState(() {
              currentLayer = layer;
            });
           
          }
        }
        // Update progress based on layer count
        if (widget.totalLayers > 0) {
          setState(() {
            progress = (currentLayer * 100 / widget.totalLayers);
          });
          if (kDebugMode) {
            print('[DEBUG] >>>>>>>>> Progress: $progress');
             print('[DEBUG] >>>>>>>>> Layer : $currentLayer');
          }
        }

        // Start timer if there is no m73
        if (!hasM73 && _startTime == null) {
          _startTime = DateTime.now();
          _timer = Timer.periodic(Duration(seconds: 1), (_) {
            final duration = DateTime.now().difference(_startTime!);
            setState(() {
              currentTime =
                  '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
            });
          });
        }
      }

      if (line.isEmpty || line.startsWith(';')) continue;

      if (kDebugMode) {
        if (hasM73 && line.contains('M73')) {
          print('[DEBUG] >>>>>>>>> $line');
          print('[DEBUG] >>>>>>>>> Progress: $progress');
          print('[DEBUG] >>>>>>>>> Layer: $currentLayer'); 
        } else {
          print('[DEBUG] $line');
        }
        waitingForOk = true;
        await Future.delayed(Duration(milliseconds: 80));
        waitingForOk = false;
      } else {
        usbService.sendGCode('$line\n', context);
        waitingForOk = true;
        break;
      }
    }

    if (currentLineIndex >= gcodeLines.length) {
      printing = false;
      _serialSub?.cancel();
      paused = false;
      _timer?.cancel();
      _startTime = null;
      hasM73 = false;
      currentLayer = 0;
      currentTime = '0:00';
      gcodeLines.clear();
      currentLineIndex = 0;
      waitingForOk = false;
      setState(() {});
      Future.delayed(Duration(milliseconds: 300), () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Print_Finished'.tr()),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop();
                },
                child: Text('OK'.tr()),
              ),
            ],
          ),
        );
      });
    }
  }

  void pausePrintJob(UsbConnectionService usbService, BuildContext context) {
    if (usbService.port != null) usbService.sendGCode("M25\n", context);
    paused = true;
    setState(() {});
  }

  void resumePrintJob(UsbConnectionService usbService, BuildContext context) {
    if (usbService.port != null) usbService.sendGCode("M24\n", context);
    paused = false;
    _sendNextLine(usbService, context);
    setState(() {});
  }

  void cancelPrintJob(UsbConnectionService usbService, BuildContext context) {
    Future.delayed(Duration(milliseconds: 300), () {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Color.fromARGB(255, 210, 156, 106)),
              SizedBox(width: 8),
              Text('Cancel_Print'.tr()),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                printing = false;
                paused = false;
                currentLayer = 0;
                currentTime = '0:00';
                gcodeLines.clear();
                currentLineIndex = 0;
                waitingForOk = false;
                hasM73 = false;
                _startTime = null;
                _timer?.cancel();
                _timer = null;
                _serialSub?.cancel();
                usbService.sendGCode(
                    "G90\nG1 X0 Y220 Z15\nM140 S0\nM104 S0\nM106 S0", context);
                setState(() {});

                Navigator.of(context).pop(); // close dialog
                Navigator.of(context).pop(); // return to previous page (Home)
              },
              child: Text('OK'.tr()),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // just close dialog
              },
              child: Text('Cancel'.tr()),
            ),
          ],
        ),
      );
    });
  }

  void _showFanSpeedInputDialog(
      UsbConnectionService usbService, BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Set_Fan_Speed'.tr()),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: "Enter_fan_speed".tr()),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value != null && value >= 0 && value <= 255) {
                usbService.sendGCode("M106 S$value\n", context);
              }
              Navigator.pop(context);
            },
            child: Text('OK'.tr()),
          ),
        ],
      ),
    );
  }

  void _showZOffsetDialog(
      UsbConnectionService usbService, BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Set_Z_Offset'.tr()),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true, signed: true),
          decoration: InputDecoration(hintText: "ex_string".tr()),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              if (value != null && value >= -2.0 && value <= 2.0) {
                usbService.sendGCode("M851 Z$value\n", context);
              }
              Navigator.pop(context);
            },
            child: Text('OK'.tr()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tempSvc = Provider.of<TemperatureService>(context);
    final usbService = Provider.of<UsbConnectionService>(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            // LEFT: Thumbnail Card
            Expanded(
              flex: 1,
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(7.0),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Column(
                          children: [
                            SizedBox(
                                width: 300,
                                height: 22,
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween<double>(
                                      begin: 0, end: progress / 100),
                                  duration: Duration(milliseconds: 500),
                                  builder: (context, value, child) {
                                    return LinearProgressIndicator(
                                      value: value.clamp(0.0, 1.0),
                                      minHeight: 22,
                                    );
                                  },
                                )),
                            const SizedBox(height: 3),
                            Text('${(progress).toStringAsFixed(0)}%',
                                style: const TextStyle(
                                    fontSize: 27,
                                    color: Color.fromARGB(255, 123, 214, 223))),
                          ],
                        ),
                      ),
                      if (decodedThumbnail != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Image.memory(
                            decodedThumbnail!,
                            height: 180,
                            fit: BoxFit.contain,
                          ),
                        ),
                      Column(
                        children: [
                          Text(
                            widget.filename,
                            style: const TextStyle(
                                fontSize: 30, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            paused
                                ? 'Status_Paused'.tr()
                                : (printing
                                    ? 'Status_Printing'.tr()
                                    : 'Status_Idle'.tr()),
                            style: const TextStyle(
                                fontSize: 25,
                                color: Color.fromARGB(179, 130, 236, 164),
                                fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(width: 10),

            // RIGHT: Controls Grid Card
            Expanded(
              flex: 1,
              child: Card(
                color: Colors.white.withAlpha((0.05 * 255).round()),
                elevation: 2,
                child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: GridView.count(
                      crossAxisCount: 3,
                      childAspectRatio: 1.1, // Compact square
                      mainAxisSpacing: 3,
                      crossAxisSpacing: 3,
                      physics: const NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      children: [
                        _buildActionCard(
                          Image.asset(
                            'assets/icons/hotend_temp.png',
                            fit: BoxFit.fitHeight,
                            height: 46,
                            width: 46,
                          ),
                          '${tempSvc.hotendTemp} / ${tempSvc.targetHotend.toStringAsFixed(0)}°C',
                          () => _showTempInputDialog(
                              'Hotend'.tr(),
                              tempSvc.hotendTemp,
                              (val) => usbService.sendGCode(
                                  "M104 S$val\n", context)),
                        ),
                        _buildActionCard(
                          Image.asset(
                            'assets/icons/bed_icon.png',
                            fit: BoxFit.fitHeight,
                            height: 46,
                            width: 46,
                          ),
                          '${tempSvc.bedTemp} / ${tempSvc.targetBed.toStringAsFixed(0)}°C',
                          () => _showTempInputDialog(
                              'Bed'.tr(),
                              tempSvc.bedTemp,
                              (val) => usbService.sendGCode(
                                  "M140 S$val\n", context)),
                        ),
                        _buildActionCard(
                            Icons.wind_power_rounded,
                            'Fan'.tr() + ' ${tempSvc.fanSpeed}',
                            () =>
                                _showFanSpeedInputDialog(usbService, context)),
                        _buildInfoCard(Icons.layers,
                            '$currentLayer / ${widget.totalLayers}'),
                        _buildInfoCard(Icons.schedule,
                            '$currentTime / ${widget.totalTime}'),
                        _buildActionCard(
                            Icons.vertical_align_center,
                            'Z Offset',
                            () => _showZOffsetDialog(usbService, context)),
                        _buildActionCard(Icons.play_arrow, 'Start'.tr(),
                            () => startPrintJob(usbService, context),
                            enabled: !printing),
                        paused
                            ? _buildActionCard(Icons.play_arrow, 'Resume'.tr(),
                                () => resumePrintJob(usbService, context),
                                enabled: printing)
                            : _buildActionCard(Icons.pause, 'Pause'.tr(),
                                () => pausePrintJob(usbService, context),
                                enabled: printing && !paused),
                        _buildActionCard(Icons.cancel, 'Stop'.tr(),
                            () => cancelPrintJob(usbService, context),
                            enabled: printing),
                      ],
                    )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(dynamic iconOrImage, String text) {
    Widget iconWidget;
    if (iconOrImage is IconData) {
      iconWidget = Icon(iconOrImage, size: 32);
    } else if (iconOrImage is Widget) {
      iconWidget = iconOrImage;
    } else {
      iconWidget = const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            iconWidget,
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(dynamic iconOrImage, String label, VoidCallback onTap,
      {bool enabled = true}) {
    Widget iconWidget;
    if (iconOrImage is IconData) {
      iconWidget = Icon(iconOrImage, size: 32);
    } else if (iconOrImage is Widget) {
      iconWidget = iconOrImage;
    } else {
      iconWidget = const SizedBox.shrink();
    }

    return Card(
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconWidget,
              const SizedBox(height: 10),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}
