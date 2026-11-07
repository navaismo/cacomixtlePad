import 'package:CacomixtlePad/pages/bed_level.dart';
import 'package:CacomixtlePad/pages/extrude_retract.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/usb_connection_service.dart';
import '../widgets/number_input_dialog.dart';
import '../widgets/responsive_layout.dart';

class PreparePage extends StatelessWidget {
  const PreparePage({super.key});

  Future<void> _showZOffsetDialog(BuildContext context) async {
    final usb = context.read<UsbConnectionService>();
    final value = await showNumberInputDialog(context,
        title: 'Set_Z_Offset'.tr(),
        hint: 'ex_string'.tr(),
        minimum: -2,
        maximum: 2);
    if (value != null && context.mounted) {
      usb.sendGCode('M851 Z$value\n', context);
    }
  }

  void _confirmDisableMotors(BuildContext context) {
    final usbService =
        Provider.of<UsbConnectionService>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.all(12),
        title: Text('Disable_All_Motors'.tr()),
        content: Text('disable_motors'.tr()),
        actions: [
          TextButton(
            onPressed: () {
              usbService.sendGCode("M84\nG92.9 Z0\n", context);
              Navigator.of(context).pop();
            },
            child: Text('Yes'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'.tr()),
          ),
        ],
      ),
    );
  }

  void _navigatePlaceholder(BuildContext context, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExtrudeRetractPage(),
      ),
    );
  }

  void _navigateBLholder(BuildContext context, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BedLevelPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageScrollView(
        child: ControlWrap(minWidth: 160, maxColumns: 4, children: [
          ControlCard(
              icon: const Icon(Icons.vertical_align_center, size: 40),
              label: 'Z_Offset'.tr(),
              onTap: () => _showZOffsetDialog(context)),
          ControlCard(
              icon: Image.asset('assets/icons/extrude1.png', height: 48),
              label: 'Extrude'.tr(),
              onTap: () => _navigatePlaceholder(context, 'Extrude')),
          ControlCard(
              icon: Image.asset('assets/icons/retract.png', height: 48),
              label: 'Retract'.tr(),
              onTap: () => _navigatePlaceholder(context, 'Retract')),
          ControlCard(
              icon: Image.asset('assets/icons/stepper.png', height: 48),
              label: 'Disable_Motors'.tr(),
              onTap: () => _confirmDisableMotors(context)),
          ControlCard(
              icon: Image.asset('assets/icons/bedlevel4.png', height: 48),
              label: 'Bed_Level'.tr(),
              onTap: () => _navigateBLholder(context, 'Bed_Level'.tr())),
        ]),
      );
}
