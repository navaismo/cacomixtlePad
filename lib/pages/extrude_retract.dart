import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:CacomixtlePad/services/usbConn_svc.dart';
import 'package:CacomixtlePad/services/temp_svc.dart';

class ExtrudeRetractPage extends StatefulWidget {
  @override
  _ExtrudeRetractPageState createState() => _ExtrudeRetractPageState();
}

class _ExtrudeRetractPageState extends State<ExtrudeRetractPage> {
  double _currentTemperature = 0.0;
  double _targetTemperature = 0.0;
  double _extrudeAmount = 0.0;
  bool _isHeating = false;
  bool _isExtrude = true; // true for extrude, false for retract
  Timer? _tempPollingTimer;

  @override
  void initState() {
    super.initState();
    _startTemperaturePolling();
  }

  @override
  void dispose() {
    _tempPollingTimer?.cancel();
    super.dispose();
  }

  void _startTemperaturePolling() {
    final tempSvc = Provider.of<TemperatureService>(context, listen: false);
    _tempPollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      setState(() {
        _currentTemperature = double.tryParse(tempSvc.hotendTemp) ?? 0.0;
      });
    });
  }

  void _setTemperature(UsbConnectionService usbService, BuildContext context,
      double temperature, TemperatureService tempSvc) {
    setState(() {
      tempSvc.targetHotend = temperature;
      _targetTemperature = temperature;
      _isHeating = true;
    });
    usbService.sendGCode('M104 S$temperature', context);
    usbService.sendGCode('M140 S60', context); // Set bed temperature to 60°C
    // Simulate warming
    Future.delayed(Duration(seconds: 5), () {
      setState(() {
        _currentTemperature = double.parse(tempSvc.hotendTemp);
        _isHeating = false;
      });
    });
  }

  void _executeExtrudeRetract(
      UsbConnectionService usbService, BuildContext context) {
    String command =
        'G1 E${_isExtrude ? _extrudeAmount : -_extrudeAmount} F200';
    usbService.sendGCode(command, context);
  }

  void _showCustomInputDialog(
      BuildContext context, String title, Function(double) onConfirm) {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            keyboardType:
                TextInputType.numberWithOptions(decimal: true, signed: false),
            decoration: InputDecoration(hintText: 'Enter_value'.tr()),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'.tr()),
            ),
            TextButton(
              onPressed: () {
                final value = double.tryParse(controller.text);
                if (value != null) {
                  onConfirm(value);
                  Navigator.of(context).pop();
                }
              },
              child: Text('OK'.tr()),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTemperatureControls(UsbConnectionService usbService,
      BuildContext context, TemperatureService tempSvc, double fontSize) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hotend'.tr() + ' ' + 'Temp'.tr() + ': $_currentTemperature°C',
          style: TextStyle(fontSize: fontSize - 5, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 10),
        Wrap(
          spacing: 10,
          children: [200, 240, 270].map((temp) {
            final isSelected = _targetTemperature == temp.toDouble();
            return Card(
              color: isSelected ? Colors.blue : const Color.fromARGB(255, 72, 79, 93),
              elevation: isSelected ? 8 : 2,
              shape: RoundedRectangleBorder(
                side: isSelected
                    ? BorderSide(color: const Color.fromARGB(255, 226, 223, 230), width: 2)
                    : BorderSide.none,
                borderRadius: BorderRadius.circular(8),
              ),
              child: InkWell(
                onTap: () => _setTemperature(
                    usbService, context, temp.toDouble(), tempSvc),
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    '$temp°C',
                    style: TextStyle(
                      fontSize: fontSize - 5,
                      color: isSelected ? Colors.white : Colors.black,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList()
            ..add(
              Card(
                color: false ? Colors.blue : const Color.fromARGB(255, 72, 79, 93), // Custom never selected
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: InkWell(
                  onTap: () =>
                      _showCustomInputDialog(context, 'Temp'.tr(), (value) {
                    _setTemperature(usbService, context, value, tempSvc);
                  }),
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Custom'.tr(),
                      style: TextStyle(
                        fontSize: fontSize - 5,
                        color: Colors.black,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ),
        SizedBox(height: 10),
        if (_isHeating) CircularProgressIndicator(),
      ],
    );
  }

  Widget _buildExtrudeRetractControls(
      UsbConnectionService usbService, BuildContext context, double fontSize) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Extrude_Retract_Length'.tr(),
            style: TextStyle(fontSize: fontSize - 5, fontWeight: FontWeight.bold)),
        SizedBox(height: 10),
        Wrap(
          spacing: 10,
          children: [30, 50, 70].map((length) {
            final isSelected = _extrudeAmount == length.toDouble();
            return Card(
              color: isSelected ? Colors.blue : const Color.fromARGB(255, 72, 79, 93),
              elevation: isSelected ? 8 : 2,
              shape: RoundedRectangleBorder(
                side: isSelected
                    ? BorderSide(color: const Color.fromARGB(255, 233, 232, 236), width: 2)
                    : BorderSide.none,
                borderRadius: BorderRadius.circular(8),
              ),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _extrudeAmount = length.toDouble();
                  });
                },
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    '${length}mm',
                    style: TextStyle(
                      fontSize: fontSize - 5,
                      color: isSelected ? Colors.white : Colors.black,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList()
            ..add(
              Card(
                color: false ? Colors.blue : const Color.fromARGB(255, 72, 79, 93), // Custom never selected
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: InkWell(
                  onTap: () =>
                      _showCustomInputDialog(context, 'Length'.tr(), (value) {
                    setState(() {
                      _extrudeAmount = value;
                    });
                  }),
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Custom'.tr(),
                      style: TextStyle(
                        fontSize: fontSize - 5,
                        color: Colors.black,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ),
        SizedBox(height: 10),
        Wrap(
          spacing: 10,
          children: [
            Card(
              color: _isExtrude ? Colors.blue : Colors.white,
              elevation: _isExtrude ? 6 : 2,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _isExtrude = true;
                  });
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: _isExtrude ? 20 : 12, // Bigger if selected
                    horizontal: _isExtrude ? 32 : 12, // Bigger if selected
                  ),
                  child: Text(
                    'Extrude'.tr(),
                    style: TextStyle(
                      fontSize: fontSize - 3, // Slightly bigger font if selected
                      color: _isExtrude ? Colors.white : Colors.black,
                      fontWeight: _isExtrude ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
            Card(
              color: !_isExtrude ? Colors.blue : Colors.white,
              elevation: !_isExtrude ? 6 : 2,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _isExtrude = false;
                  });
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: !_isExtrude ? 20 : 12, // Bigger if selected
                    horizontal: !_isExtrude ? 32 : 12, // Bigger if selected
                  ),
                  child: Text(
                    'Retract'.tr(),
                    style: TextStyle(
                      fontSize: fontSize - 3, // Slightly bigger font if selected
                      color: !_isExtrude ? Colors.white : Colors.black,
                      fontWeight: !_isExtrude ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 10),
        if (_currentTemperature > 195.5 && _currentTemperature >= _targetTemperature && !_isHeating)
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
          textStyle: TextStyle(fontSize: fontSize + 6, fontWeight: FontWeight.bold),
          padding: EdgeInsets.symmetric(vertical: 18),
              ),
              onPressed: () => _executeExtrudeRetract(usbService, context),
              child: Text(_isExtrude ? 'Extrude'.tr() : 'Retract'.tr()),
            ),
          ),
      ],
    );
  }

  Widget _buildXYZControls(
      UsbConnectionService usbService, BuildContext context, double iconSize) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 50),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Card(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_up),
                        iconSize: iconSize * 1.5,
                        onPressed: () => usbService.sendGCode(
                            "G91\nG0 Y10 F3000\nG90", context),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_left),
                            iconSize: iconSize * 1.5,
                            onPressed: () => usbService.sendGCode(
                                "G91\nG0 X-10 F3000\nG90", context),
                          ),
                          IconButton(
                            icon: const Icon(Icons.home),
                            iconSize: iconSize * 1.5,
                            onPressed: () =>
                                usbService.sendGCode("G28", context),
                          ),
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_right),
                            iconSize: iconSize * 1.5,
                            onPressed: () => usbService.sendGCode(
                                "G91\nG0 X10 F3000\nG90", context),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down),
                        iconSize: iconSize * 1.5,
                        onPressed: () => usbService.sendGCode(
                            "G91\nG0 Y-10 F3000\nG90", context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
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
                        onPressed: () => usbService.sendGCode(
                            "G91\nG0 Z2 F300\nG90", context),
                      ),
                      const SizedBox(height: 20),
                      IconButton(
                        icon: const Icon(Icons.arrow_downward),
                        iconSize: iconSize * 1.5,
                        onPressed: () => usbService.sendGCode(
                            "G91\nG0 Z-2 F300\nG90", context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tempSvc = Provider.of<TemperatureService>(context);
    final usbService = Provider.of<UsbConnectionService>(context);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;
          final iconSize = screenWidth < 600
              ? 32.0
              : screenWidth < 900
                  ? 40.0
                  : 48.0;
          final fontSize = screenWidth < 600
              ? 16.0
              : screenWidth < 900
                  ? 18.0
                  : 20.0;

          if (screenWidth < 600) {
            // Small screens
            return SingleChildScrollView(
              padding: EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildXYZControls(usbService, context, iconSize),
                  SizedBox(height: 10),
                  _buildTemperatureControls(
                      usbService, context, tempSvc, fontSize),
                  SizedBox(height: 10),
                  _buildExtrudeRetractControls(usbService, context, fontSize),
                ],
              ),
            );
          } else {
            // Medium and Large screens
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                      child: _buildXYZControls(usbService, context, iconSize)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTemperatureControls(
                            usbService, context, tempSvc, fontSize),
                        SizedBox(height: 20),
                        _buildExtrudeRetractControls(
                            usbService, context, fontSize),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }
}
