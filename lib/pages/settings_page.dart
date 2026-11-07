import 'package:CacomixtlePad/pages/material_values.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../services/usb_connection_service.dart';
import '../services/app_info_service.dart';
import '../widgets/responsive_layout.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _changeLanguage(BuildContext context) => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.all(12),
          title: Text('Change_Language'.tr()),
          content: SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final locale in context.supportedLocales)
                ListTile(
                  title: Text(locale.languageCode.toUpperCase()),
                  trailing:
                      locale == context.locale ? const Icon(Icons.check) : null,
                  onTap: () async {
                    await context.setLocale(locale);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                ),
            ]),
          ),
        ),
      );

  Future<void> _showDetails(
          BuildContext context, String title, Map<String, String?> details,
          {bool logo = false}) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.all(12),
          title: Text(title),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (logo)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Image.asset('assets/icons/splash5_padded.png',
                        height: 96),
                  ),
                for (final entry in details.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.key,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary)),
                        const SizedBox(height: 4),
                        SelectableText(entry.value ?? '-'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text('Close'.tr()))
          ],
        ),
      );

  Future<void> _showPrinterInfo(BuildContext context) async {
    final details =
        await context.read<UsbConnectionService>().getFWInfo(context);
    if (context.mounted) {
      await _showDetails(context, 'Printer_Info'.tr(), details);
    }
  }

  Future<void> _showPrinterStatistics(BuildContext context) async {
    final details =
        await context.read<UsbConnectionService>().getStats(context);
    if (context.mounted) {
      await _showDetails(context, 'Printer_Statistics'.tr(), details);
    }
  }

  Future<void> _editMaterialValues(BuildContext context) =>
      Navigator.push<void>(context,
          MaterialPageRoute(builder: (_) => const MaterialValuesPage()));

  Future<void> _savePrinterSettings(BuildContext context) async {
    final usb = context.read<UsbConnectionService>();
    if (!await usb.awaitGcode('M500', context) || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.all(12),
        content: Text('Settings_saved'.tr()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('OK'.tr()))
        ],
      ),
    );
  }

  Future<void> _aboutApp(BuildContext context) async {
    final version = await AppInfoService.getVersion();
    if (!context.mounted) return;
    await _showDetails(
        context,
        'About'.tr(),
        {
          'Version': version,
          'Build date': '2026-11-07',
          'Author': 'Navaismo',
          'Info': 'CacomixtlePad is an Android app for controlling the 3D printer '
              'Ender 3 V3 SE and probably other printers with Marlin firmware.',
          'Source code': 'https://github.com/navaismo/cacomixtlePad',
          'Disclaimer':
              'This app is not affiliated with Creality or any other company. '
                  'Use at your own risk. The author is not responsible for any damage '
                  'caused to your printer or any other device.',
          'Need help': 'Open an issue on GitHub.',
        },
        logo: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Settings'.tr())),
        body: PageScrollView(
          child: ControlWrap(minWidth: 170, children: [
            ControlCard(
                icon: const Icon(Icons.translate, size: 32),
                label: 'Change_Language'.tr(),
                onTap: () => _changeLanguage(context)),
            ControlCard(
                icon: const Icon(Icons.system_update_alt_rounded, size: 32),
                label: 'Printer_Info'.tr(),
                onTap: () => _showPrinterInfo(context)),
            ControlCard(
                icon: const Icon(Icons.manage_history_rounded, size: 32),
                label: 'Printer_Statistics'.tr(),
                onTap: () => _showPrinterStatistics(context)),
            ControlCard(
                icon: const Icon(Icons.view_in_ar_rounded, size: 32),
                label: 'Edit_Material_Values'.tr(),
                onTap: () => _editMaterialValues(context)),
            ControlCard(
                icon: const Icon(Icons.browser_updated_rounded, size: 32),
                label: 'Save_Printer_Settings'.tr(),
                onTap: () => _savePrinterSettings(context)),
            ControlCard(
                icon: const Icon(Icons.perm_device_info_rounded, size: 32),
                label: 'About'.tr(),
                onTap: () => _aboutApp(context)),
          ]),
        ),
      );
}
