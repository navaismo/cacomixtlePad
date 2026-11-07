import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/temp_svc.dart';
import '../services/material_presets.dart';
import '../services/usb_connection_service.dart';
import '../widgets/movement_controls.dart';
import '../widgets/number_input_dialog.dart';
import '../widgets/responsive_layout.dart';

class HomePage extends StatelessWidget {
  final String apiUrl;
  final String slicerUrl;
  final String apiKey;

  const HomePage({
    super.key,
    required this.apiUrl,
    required this.slicerUrl,
    this.apiKey = '',
  });

  Future<void> _showPreheatDialog(BuildContext context) async {
    final usb = context.read<UsbConnectionService>();
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.all(12),
        title: Text('Select_Material'.tr()),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final material in MaterialPresets.materials)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ElevatedButton(
                    onPressed: () {
                      final hotend =
                          MaterialPresets.read(prefs, material, isBed: false);
                      final bed =
                          MaterialPresets.read(prefs, material, isBed: true);
                      usb.sendGCode('M104 S$hotend\nM140 S$bed', context);
                      Navigator.pop(dialogContext);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Text(material),
                          Text(
                              '${'Hotend'.tr()}: ${MaterialPresets.read(prefs, material, isBed: false).toStringAsFixed(0)}°C'),
                          Text(
                              '${'Bed'.tr()}: ${MaterialPresets.read(prefs, material, isBed: true).toStringAsFixed(0)}°C'),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showTempInputDialog(BuildContext context, String label,
      double currentValue, String commandPrefix) async {
    final usb = context.read<UsbConnectionService>();
    final value = await showNumberInputDialog(context,
        title: '${'Set'.tr()} $label ${'Temp'.tr()}',
        hint: 'Enter_temperature'.tr(),
        initialValue: currentValue,
        maximum: commandPrefix.startsWith('M140') ? 150 : 300);
    if (value != null && context.mounted) {
      usb.sendGCode('$commandPrefix$value', context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final temperature = context.watch<TemperatureService>();
    final usb = context.watch<UsbConnectionService>();
    return PageScrollView(
      child: AdaptiveColumns(
        trailingFirstWhenStacked: true,
        leadingFlex: 1,
        trailingFlex: 2,
        leading: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Cacomixtle-Pad v1.1.1\nEnder 3 V3 SE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(255, 98, 185, 222))),
              const SizedBox(height: 12),
              Text('API URL: $apiUrl\nSlicer URL: $slicerUrl',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14)),
              if (apiKey.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text('Api_key'.tr()),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      scrollable: true,
                      insetPadding: const EdgeInsets.all(12),
                      title: Text('Api_key'.tr()),
                      content: SelectableText(apiKey),
                      actions: [
                        TextButton(
                          onPressed: () async {
                            await Clipboard.setData(
                                ClipboardData(text: apiKey));
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          },
                          child: Text('Copy'.tr()),
                        )
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Image.asset('assets/icons/printer_side.png',
                  fit: BoxFit.contain, height: 150),
            ]),
          ),
        ),
        trailing: Column(mainAxisSize: MainAxisSize.min, children: [
          ControlWrap(minWidth: 130, maxColumns: 4, children: [
            _tempCard(context, 'Hotend'.tr(), 'M104 S', temperature.hotendTemp,
                temperature.targetHotend, 'assets/icons/hotend_temp.png'),
            _tempCard(context, 'Bed'.tr(), 'M140 S', temperature.bedTemp,
                temperature.targetBed, 'assets/icons/bed_icon.png'),
            ControlCard(
                icon: const Icon(Icons.whatshot, size: 28),
                label: 'Preheat'.tr(),
                onTap: () => _showPreheatDialog(context)),
            ControlCard(
                icon: const Icon(Icons.ac_unit, size: 28),
                label: 'Cooldown'.tr(),
                onTap: () => usb.sendGCode('M140 S0\nM104 S0', context)),
          ]),
          const SizedBox(height: 12),
          MovementControls(
              onCommand: (command) => usb.sendGCode(command, context)),
        ]),
      ),
    );
  }

  Widget _tempCard(BuildContext context, String label, String commandPrefix,
          String current, double target, String asset) =>
      ControlCard(
        icon: Image.asset(asset, height: 28, width: 28),
        label: '$label\n$current / ${target.toStringAsFixed(0)}°C',
        onTap: () =>
            _showTempInputDialog(context, label, target, commandPrefix),
      );
}
