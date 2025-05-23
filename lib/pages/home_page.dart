import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/temp_svc.dart';
import '../services/usbConn_svc.dart';

class HomePage extends StatelessWidget {
  final String API_URL;
  final String Slicer_URL;

  const HomePage({
    super.key,
    required this.API_URL,
    required this.Slicer_URL, 
  });

  double _defaultHotend(String mat) {
    switch (mat) {
      case 'PLA':
        return 200;
      case 'TPU':
        return 220;
      case 'PETG':
        return 240;
      case 'ABS':
        return 270;
      default:
        return 200;
    }
  }

  double _defaultBed(String mat) {
    switch (mat) {
      case 'PLA':
        return 61;
      case 'TPU':
        return 65;
      case 'PETG':
        return 72;
      case 'ABS':
        return 90;
      default:
        return 60;
    }
  }

  void _showPreheatDialog(BuildContext context) async {
    final usb = Provider.of<UsbConnectionService>(context, listen: false);
    final prefs = await SharedPreferences.getInstance();

    final List<String> materials = ['PLA', 'PETG', 'TPU', 'ABS'];
    final List<List<dynamic>> materialValues = [];

    for (var mat in materials) {
      final hotend = prefs.getDouble('hotend_$mat') ?? _defaultHotend(mat);
      final bed = prefs.getDouble('bed_$mat') ?? _defaultBed(mat);
      materialValues.add([mat, hotend, bed]);
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
      title: Text('Select_Material'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
        for (var mat in materialValues)
          ElevatedButton(
          onPressed: () {
            usb.sendGCode("M104 S${mat[1]}\nM140 S${mat[2]}", context);
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
            Text(mat[0] as String),
            Text(
              "Hotend: ${mat[1].toStringAsFixed(0)}°C, Bed: ${mat[2].toStringAsFixed(0)}°C",
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
            ],
          ),
          )
        ],
      ),
      ),
    );
  }

  void _showTempInputDialog(BuildContext context, String label,
      double currentValue, String commandPrefix) {
    final controller =
        TextEditingController(text: currentValue.toStringAsFixed(0));
    final usb = Provider.of<UsbConnectionService>(context, listen: false);
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
                usb.sendGCode("$commandPrefix$value", context);
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
    final usb = Provider.of<UsbConnectionService>(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;
        //final isTablet = screenWidth >= 600;

        // Scale factors based on screen width
        final scaleFactor = screenWidth / 600; // 600 as a base reference
        final iconSize = 22.0 * scaleFactor;
        final fontSize = 14.0 * scaleFactor;
        final titleFontSize = 13.0 * scaleFactor;
        final infoFontSize = 8.5 * scaleFactor;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              children: [
                // Left column: Image and title
                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      Text(
                        'Cacomixtle-Pad v1.1.0\nEnder 3 V3 SE\n',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.bold,
                          color: const Color.fromARGB(255, 98, 185, 222),
                        ),
                      ),
                       const SizedBox(height: 10),
                       Text(
                        'API URL:  $API_URL\nSlicer URL:  $Slicer_URL',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: infoFontSize,
                          fontWeight: FontWeight.bold,
                          color: const Color.fromARGB(255, 218, 208, 243),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Expanded(
                        child: Center(
                          child: Image.asset(
                            'assets/icons/printer_side.png',
                            fit: BoxFit.contain,
                            height: screenHeight * 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const VerticalDivider(
                    width: 1, thickness: 1, color: Colors.grey),

                // Right column: controls
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      // Row of temperature and preheating controls
                      Row(
                        children: [
                          _tempCard(
                              context,
                              'Hotend'.tr(),
                              'M104 S',
                              tempSvc.hotendTemp,
                              tempSvc.targetHotend,
                              'assets/icons/hotend_temp.png',
                              iconSize,
                              fontSize),
                          _tempCard(
                              context,
                              'Bed'.tr(),
                              'M140 S',
                              tempSvc.bedTemp,
                              tempSvc.targetBed,
                              'assets/icons/bed_icon.png',
                              iconSize,
                              fontSize),
                          _simpleCard(
                              Icons.whatshot,
                              'Preheat'.tr(),
                              () => _showPreheatDialog(context),
                              iconSize,
                              fontSize),
                          _simpleCard(
                              Icons.ac_unit,
                              'Cooldown'.tr(),
                              () => usb.sendGCode("M140 S0\nM104 S0", context),
                              iconSize,
                              fontSize),
                        ],
                      ),
                      const SizedBox(height: 7),
                      // XYZ Y Home Movement Controls
                      Expanded(
                        child: Row(
                          children: [
                            // XY Y Home Movement Controls
                            Expanded(
                              flex: 3,
                              child: Card(
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        icon:
                                            const Icon(Icons.keyboard_arrow_up),
                                        iconSize: iconSize * 1.5,
                                        onPressed: () => usb.sendGCode(
                                            "G91\nG0 Y-10 F3000\nG90", context),
                                      ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                                Icons.keyboard_arrow_left),
                                            iconSize: iconSize * 1.5,
                                            onPressed: () => usb.sendGCode(
                                                "G91\nG0 X-10 F3000\nG90",
                                                context),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.home),
                                            iconSize: iconSize * 1.5,
                                            onPressed: () =>
                                                usb.sendGCode("G28", context),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                                Icons.keyboard_arrow_right),
                                            iconSize: iconSize * 1.5,
                                            onPressed: () => usb.sendGCode(
                                                "G91\nG0 X10 F3000\nG90",
                                                context),
                                          ),
                                        ],
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.keyboard_arrow_down),
                                        iconSize: iconSize * 1.5,
                                        onPressed: () => usb.sendGCode(
                                            "G91\nG0 Y10 F3000\nG90", context),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            // Z MOVEMENT CONTROLS
                            Expanded(
                              flex: 1,
                              child: Card(
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.arrow_upward),
                                        iconSize: iconSize * 1.5,
                                        onPressed: () => usb.sendGCode(
                                            "G91\nG0 Z2 F300\nG90", context),
                                      ),
                                      const SizedBox(height: 20),
                                      IconButton(
                                        icon: const Icon(Icons.arrow_downward),
                                        iconSize: iconSize * 1.5,
                                        onPressed: () => usb.sendGCode(
                                            "G91\nG0 Z-2 F300\nG90", context),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tempCard(
      BuildContext context,
      String label,
      String commandPrefix,
      String current,
      double target,
      String asset,
      double iconSize,
      double fontSize) {
    return Expanded(
      child: Card(
        child: InkWell(
          onTap: () =>
              _showTempInputDialog(context, label, target, commandPrefix),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Image.asset(asset, height: iconSize, width: iconSize),
                const SizedBox(height: 10),
                Text('$current / ${target.toStringAsFixed(0)}°C',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: fontSize - 5)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _simpleCard(IconData icon, String label, VoidCallback onTap,
      double iconSize, double fontSize) {
    return Expanded(
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Icon(icon, size: iconSize),
                const SizedBox(height: 10),
                Text(label,
                    style: TextStyle(fontSize: fontSize - 5),
                    textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
