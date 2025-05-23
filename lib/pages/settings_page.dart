import 'package:CacomixtlePad/pages/material_values.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../services/usbConn_svc.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({Key? key}) : super(key: key);

  Future<void> _changeLanguage(BuildContext context) async {
    final locales = context.supportedLocales;
    final currentLocale = context.locale;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Change_Language'.tr()),
          content: SizedBox(
            height: 150,
            child: ListWheelScrollView.useDelegate(
              itemExtent: 50,
              childDelegate: ListWheelChildBuilderDelegate(
                builder: (context, index) {
                  final locale = locales[index];
                  return GestureDetector(
                    onTap: () {
                      context.setLocale(locale);
                      Navigator.of(context).pop();
                    },
                    child: Center(
                      child: Text(
                        locale.languageCode.toUpperCase(),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: locale == currentLocale ? FontWeight.bold : FontWeight.normal,
                          color: locale == currentLocale ? Theme.of(context).colorScheme.primary : null,
                        ),
                      ),
                    ),
                  );
                },
                childCount: locales.length,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPrinterInfo(BuildContext context) async {
    final usbService = Provider.of<UsbConnectionService>(context, listen: false);
    final Map<String, String?> printerInfo = await usbService.getFWInfo(context);
   
    print(printerInfo);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              //Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('Printer_Info'.tr()),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: printerInfo.entries.map((e) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              e.key,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
                ),
                const SizedBox(width: 10),
                Expanded(
            child: Text(
              e.value ?? '-',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
                ),
              ],
            ),
          );
              }).toList(),
            ),
          ),
          actions: [
            TextButton.icon(
              //icon: Icon(Icons.close, color: Theme.of(context).colorScheme.primary),
              label: Text('Close'.tr()),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

 

  Future<void> _showPrinterStatistics(BuildContext context) async {
     final usbService = Provider.of<UsbConnectionService>(context, listen: false);
    final Map<String, String?> printerStats = await usbService.getStats(context);
   
    print(printerStats);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              //Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('Printer_Info'.tr()),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: printerStats.entries.map((e) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              e.key,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
                ),
                const SizedBox(width: 10),
                Expanded(
            child: Text(
              e.value ?? '-',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
                ),
              ],
            ),
          );
              }).toList(),
            ),
          ),
          actions: [
            TextButton.icon(
              //icon: Icon(Icons.close, color: Theme.of(context).colorScheme.primary),
              label: Text('Close'.tr()),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }


  Future<void> _editMaterialValues(BuildContext context) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>  MaterialValuesPage(),
      ),
    );
  }

  Future<void> _savePrinterSettings(BuildContext context) async {
    final usbService = Provider.of<UsbConnectionService>(context, listen: false);
    usbService.sendGCode('M500', context);
    await Future.delayed(const Duration(seconds: 2));
      showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Text('Settings_saved'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'.tr()),
            ),
          ],
        );
      },
    );  
  }

  Future<void> _aboutApp(BuildContext context) async {
   
   final obj = {
        "Version": "1.1.0",
        "Build_Date": "2025-05-23",
        "Info": "CacomixtlePad is an Android app for controlling the \n                       3D printer Ender 3 V3 SE\n And probably other printers with Marlin firmware.",
        "Author": "Navaismo",
        "Source_Code": "https://github.com/navaismo/cacomixtlePad",
        "Disclaimer": "This app is not affiliated with Creality or any other company. \nUse at your own risk. \nThe author is not responsible for \nany damage caused to your printer or any other device.",
        "Need Help": "Open an issue on GitHub.",
      };
    showDialog(
      context: context,
      builder: (context) {
      return AlertDialog(
        title: Row(
        children: [
          Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text('About'.tr(), style: TextStyle(fontWeight: FontWeight.bold)),
        ],
        ),
        content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // App Logo 
          Center(
            child: CircleAvatar(
            radius: 60,
            backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
            child: Image.asset(
                'assets/icons/splash5_padded.png',
                width: 120,
                height: 120,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Version & Build Date
          Row(
            children: [
            const SizedBox(width: 12),  
            Icon(Icons.verified, color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text('Version: ', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(obj["Version"] ?? "-"),
            const SizedBox(width: 20),
            Icon(Icons.calendar_today, color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(obj["Build_Date"] ?? "-"),
            const SizedBox(width: 20),
            Icon(Icons.person, color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text('Author: ', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(obj["Author"] ?? "-"),
            ],
          ),
          const SizedBox(height: 12),
          
          
          const SizedBox(height: 12),
          // Info
          Text(
            obj["Info"] ?? "-",
            style: TextStyle(fontSize: 17, color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(height: 20),
          // Source Code
          Row(
            children: [
            Icon(Icons.code, color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text('Source Code:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            Flexible(
              child: InkWell(
              onTap: () async {
                final url = obj["Source_Code"];
                if (url != null) {
                // TODO: Open URL in browser
                }
              },
              child: Text(
                obj["Source_Code"] ?? "-",
                style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              ),
            ),
            ],
          ),
          const SizedBox(height: 20),
          // Disclaimer
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber[800], size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
              obj["Disclaimer"] ?? "-",
              style: TextStyle(
                color: Colors.amber[800],
                fontSize: 15,
                fontStyle: FontStyle.italic,
              ),
              ),
            ),
            ],
          ),
          const SizedBox(height: 20),
          // Need Help
          Row(
            children: [
            Icon(Icons.help_outline, color: Theme.of(context).colorScheme.primary, size: 18),
            const SizedBox(width: 8),
            Text('Need Help:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
              obj["Need Help"] ?? "-",
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              overflow: TextOverflow.ellipsis,
              ),
            ),
            ],
          ),
          ],
        ),
        ),
        actions: [
        TextButton.icon(
          icon: Icon(Icons.close, color: Theme.of(context).colorScheme.primary),
          label: Text('Close'.tr()),
          onPressed: () => Navigator.of(context).pop(),
        ),
        ],
      );
      },
    );
  }

  Widget _buildCard(BuildContext context, IconData iconWidget  ,String title, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.all(2), // Even smaller margins
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(iconWidget, size: 24), 
              const SizedBox(height: 6),
              Text(
                title.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13), // Smaller font
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cards = [
      _buildCard(context, Icons.translate, 'Change_Language'.tr(), () => _changeLanguage(context)),
      _buildCard(context, Icons.system_update_alt_rounded,'Printer_Info'.tr(), () => _showPrinterInfo(context)),
      _buildCard(context, Icons.manage_history_rounded,'Printer_Statistics'.tr(), () => _showPrinterStatistics(context)),
      _buildCard(context, Icons.view_in_ar_rounded,'Edit_Material_Values'.tr(), () => _editMaterialValues(context)),
      _buildCard(context, Icons.browser_updated_rounded, 'Save_Printer_Settings'.tr(), () => _savePrinterSettings(context)),
      _buildCard(context, Icons.perm_device_info_rounded,'About'.tr(), () => _aboutApp(context)),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'.tr()),
      ),
      body: Padding(
        padding: const EdgeInsets.all(2.0), // Even less padding
        child: GridView.count(
          crossAxisCount: 3, // More columns = smaller cards
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.2, // Keep cards square
          children: cards,
        ),
      ),
    );
  }
}

