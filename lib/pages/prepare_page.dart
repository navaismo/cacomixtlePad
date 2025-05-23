import 'package:CacomixtlePad/pages/bed_level.dart';
import 'package:CacomixtlePad/pages/extrude_retract.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/usbConn_svc.dart';

class PreparePage extends StatelessWidget {
  const PreparePage({super.key});

  void _showZOffsetDialog(BuildContext context) {
    final usbService =
        Provider.of<UsbConnectionService>(context, listen: false);
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title:  Text('Set_Z_Offset'.tr()),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true, signed: true),
          decoration:  InputDecoration(hintText: "ex_string".tr()),
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
            child:  Text('OK'.tr()),
          ),
        ],
      ),
    );
  }

  void _confirmDisableMotors(BuildContext context) {
    final usbService =
        Provider.of<UsbConnectionService>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title:  Text('Disable_All_Motors'.tr()),
        content:
             Text('disable_motors'.tr()),
        actions: [
          TextButton(
            onPressed: () {
              usbService.sendGCode("M84\nG92.9 Z0\n", context);
              Navigator.of(context).pop();
            },
            child:  Text('Yes'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child:  Text('Cancel'.tr()),
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


  Widget _buildActionCard(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40),
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

  // Widget _buildActionCard2(
  //     BuildContext context, String asset, String label, VoidCallback onTap) {
  //   final screen = MediaQuery.of(context).size;
  //   final isWide = screen.width > 1000;
  //   return Card(
  //     elevation: 4,
  //     child: InkWell(
  //       onTap: onTap,
  //       child: Padding(
  //         padding: const EdgeInsets.all(16),
  //         child: Column(
  //           mainAxisAlignment: MainAxisAlignment.center,
  //           children: [
  //             Image.asset(
  //               asset,
  //               width: isWide ? 40 : 36,
  //               height: isWide ? 40 : 36,
  //             ),
  //             const SizedBox(height: 10),
  //             Text(label,
  //                 textAlign: TextAlign.center,
  //                 style: const TextStyle(fontSize: 15)),
  //           ],
  //         ),
  //       ),
  //     ),
  //   );
  // }

      Widget _buildActionCard3(
      BuildContext context, String asset, String label, VoidCallback onTap) {
    final screen = MediaQuery.of(context).size;
    final isWide = screen.width > 1000;
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                asset,
                width: isWide ? 60 : 50,
                height: isWide ? 60 : 50,
              ),
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



  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.extent(
          maxCrossAxisExtent: 200,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: [
            _buildActionCard(context, Icons.vertical_align_center, 'Z_Offset'.tr(),
                () => _showZOffsetDialog(context)),
            _buildActionCard3(context, 'assets/icons/extrude1.png', 'Extrude'.tr(),
                () => _navigatePlaceholder(context, 'Extrude')),
            _buildActionCard3(context, 'assets/icons/retract.png', 'Retract'.tr(),
                () => _navigatePlaceholder(context, 'Retract')),
            _buildActionCard3(context, 'assets/icons/stepper.png', 'Disable_Motors'.tr(),
                () => _confirmDisableMotors(context)),
            _buildActionCard3(context, 'assets/icons/bedlevel4.png', 'Bed_Level'.tr(),
                () => _navigateBLholder(context, 'Bed_Level'.tr())),    
          ],
        ),
      ),
    );
  }
}
