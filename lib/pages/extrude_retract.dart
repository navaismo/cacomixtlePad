import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:CacomixtlePad/services/usb_connection_service.dart';
import 'package:CacomixtlePad/services/temp_svc.dart';
import '../widgets/movement_controls.dart';
import '../widgets/number_input_dialog.dart';
import '../widgets/responsive_layout.dart';

class ExtrudeRetractPage extends StatefulWidget {
  const ExtrudeRetractPage({super.key});

  @override
  State<ExtrudeRetractPage> createState() => _ExtrudeRetractPageState();
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
        _isHeating = _targetTemperature > 0 &&
            _currentTemperature < _targetTemperature - 2;
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
  }

  void _executeExtrudeRetract(
      UsbConnectionService usbService, BuildContext context) {
    String command =
        'M83\nG1 E${_isExtrude ? _extrudeAmount : -_extrudeAmount} F200';
    if (_extrudeAmount <= 0 || _isHeating || _currentTemperature < 170) return;
    usbService.sendGCode(command, context);
  }

  Future<void> _showCustomInputDialog(BuildContext context, String title,
      void Function(double) onConfirm) async {
    final value = await showNumberInputDialog(context,
        title: title, hint: 'Enter_value'.tr(), maximum: 300);
    if (value != null && context.mounted) onConfirm(value);
  }

  Widget _buildTemperatureControls(UsbConnectionService usb,
          BuildContext context, TemperatureService temperature) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${'Hotend'.tr()} ${'Temp'.tr()}: $_currentTemperature°C',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final value in [200, 240, 270])
              ChoiceChip(
                label: Text('$value°C'),
                selected: _targetTemperature == value.toDouble(),
                onSelected: (_) => _setTemperature(
                    usb, context, value.toDouble(), temperature),
              ),
            ActionChip(
                label: Text('Custom'.tr()),
                onPressed: () => _showCustomInputDialog(
                    context,
                    'Temp'.tr(),
                    (value) =>
                        _setTemperature(usb, context, value, temperature))),
          ]),
          if (_isHeating)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: SizedBox.square(
                  dimension: 24, child: CircularProgressIndicator()),
            ),
        ],
      );

  Widget _buildExtrudeRetractControls(
          UsbConnectionService usb, BuildContext context) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Extrude_Retract_Length'.tr(),
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final length in [30, 50, 70])
              ChoiceChip(
                label: Text('${length}mm'),
                selected: _extrudeAmount == length.toDouble(),
                onSelected: (_) =>
                    setState(() => _extrudeAmount = length.toDouble()),
              ),
            ActionChip(
                label: Text('Custom'.tr()),
                onPressed: () => _showCustomInputDialog(context, 'Length'.tr(),
                    (value) => setState(() => _extrudeAmount = value))),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
                label: Text('Extrude'.tr()),
                selected: _isExtrude,
                onSelected: (_) => setState(() => _isExtrude = true)),
            ChoiceChip(
                label: Text('Retract'.tr()),
                selected: !_isExtrude,
                onSelected: (_) => setState(() => _isExtrude = false)),
          ]),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _currentTemperature > 195.5 &&
                    _currentTemperature >= _targetTemperature &&
                    !_isHeating &&
                    _extrudeAmount > 0
                ? () => _executeExtrudeRetract(usb, context)
                : null,
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_isExtrude ? 'Extrude'.tr() : 'Retract'.tr())),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final tempSvc = context.watch<TemperatureService>();
    final usb = context.watch<UsbConnectionService>();
    return Scaffold(
      appBar: AppBar(title: Text('Extrude_Retract_Length'.tr())),
      body: PageScrollView(
        child: AdaptiveColumns(
          leading: MovementControls(
              negativeYUp: false,
              onCommand: (command) => usb.sendGCode(command, context)),
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTemperatureControls(usb, context, tempSvc),
              const SizedBox(height: 16),
              _buildExtrudeRetractControls(usb, context),
            ],
          ),
        ),
      ),
    );
  }
}
