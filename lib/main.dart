import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'pages/home_page.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shared_preferences/shared_preferences.dart';
import 'services/gcode_repository.dart';
import 'services/print_job_service.dart';
import 'services/print_job_store.dart';
import 'services/upload_api.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'pages/prepare_page.dart';
import 'pages/print_page.dart';
import 'pages/settings_page.dart';
import 'services/temp_svc.dart';
import 'services/usb_connection_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await WakelockPlus.enable();

  runApp(
    EasyLocalization(
      supportedLocales: [
        Locale('en'),
        Locale('es'),
        Locale('ru'),
        Locale('fr'),
        Locale('de'),
        Locale('it'),
        Locale('pt')
      ],
      path: 'assets/lang',
      fallbackLocale: Locale('en'),
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => UsbConnectionService()),
          ChangeNotifierProvider(create: (_) => GcodeRepository()),
          ChangeNotifierProvider(
              create: (context) =>
                  TemperatureService(context.read<UsbConnectionService>()),
              lazy: false),
          ChangeNotifierProvider(
              create: (context) => PrintJobService(
                  context.read<UsbConnectionService>(),
                  context.read<GcodeRepository>(),
                  store: PreferencesPrintJobStore())),
        ],
        child: PrinterApp(),
      ),
    ),
  );
}

class PrinterApp extends StatefulWidget {
  const PrinterApp({super.key});

  @override
  State<PrinterApp> createState() => _PrinterAppState();
}

class _PrinterAppState extends State<PrinterApp> {
  int _currentIndex = 0;
  HttpServer? _server;
  String? localIp;
  String apiUrl = '';
  String slicerUrl = '';
  final int apiPort = 8888;
  String apiKey = '';
  String? _serverError;
  bool _startingServer = false;
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _startUploadServer();
  }

  Future<void> _startUploadServer() async {
    if (_startingServer || _server != null) return;
    _startingServer = true;
    final repository = context.read<GcodeRepository>();
    try {
      await repository.ensureReady();
      final prefs = await SharedPreferences.getInstance();
      var key = prefs.getString('upload_api_key');
      if (key == null) {
        final random = Random.secure();
        key = base64UrlEncode(List.generate(32, (_) => random.nextInt(256)));
        await prefs.setString('upload_api_key', key);
      }
      String ip = '0.0.0.0';
      try {
        ip = await NetworkInfo().getWifiIP() ?? ip;
      } catch (_) {
        // Wi-Fi may be unavailable when the app starts. The server can still
        // listen on local interfaces if Wi-Fi connects later.
      }
      if (!mounted) return;
      final server = await shelf_io.serve(
        logRequests().addHandler(UploadApi(repository, apiKey: key).call),
        InternetAddress(ip),
        apiPort,
      );
      if (!mounted) {
        await server.close(force: true);
        return;
      }
      _server = server;
      setState(() {
        localIp = ip;
        apiKey = key!;
        apiUrl = 'http://$ip:$apiPort/uploads';
        slicerUrl = 'http://$ip:$apiPort';
        _serverError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _serverError = error.toString());
    } finally {
      _startingServer = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final usbService = Provider.of<UsbConnectionService>(context);
    final screen = MediaQuery.of(context).size;
    final isWide = screen.width > 1000;

    final pages = [
      HomePage(
        apiUrl: apiUrl,
        slicerUrl: slicerUrl,
        apiKey: apiKey,
      ),
      const PrintPage(),
      const PreparePage(),
      const SettingsPage(),
    ];

    return MaterialApp(
      scaffoldMessengerKey: _messenger,
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      title: 'Cacomixtle-Pad',
      theme: ThemeData.dark().copyWith(
        elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(minimumSize: const Size(48, 48))),
        filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48))),
      ),
      home: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(children: [
                if (_serverError != null)
                  SizedBox(
                    height: 48,
                    child: Row(children: [
                      IconButton(
                        icon: const Icon(Icons.info_outline),
                        tooltip: _serverError,
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            scrollable: true,
                            insetPadding: const EdgeInsets.all(12),
                            title: Text('Server_unavailable'.tr()),
                            content: Text(_serverError!.tr()),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: Text('Close'.tr()),
                              )
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                          child: Text('Server_unavailable'.tr(),
                              maxLines: 1, overflow: TextOverflow.ellipsis)),
                      IconButton(
                          onPressed: _startUploadServer,
                          tooltip: 'Retry'.tr(),
                          icon: const Icon(Icons.refresh)),
                    ]),
                  ),
                Expanded(child: pages[_currentIndex]),
              ]);
            },
          ),
        ),
        bottomNavigationBar: Builder(builder: (context) {
          if (MediaQuery.viewInsetsOf(context).bottom > 0) {
            return const SizedBox.shrink();
          }
          return SafeArea(
            top: false,
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              iconSize: isWide ? 30 : 24,
              selectedFontSize: isWide ? 16 : 12,
              unselectedFontSize: isWide ? 14 : 12,
              currentIndex: _currentIndex,
              onTap: (index) async {
                if (index == 4) {
                  try {
                    await usbService.connect();
                  } catch (error) {
                    if (context.mounted) {
                      _messenger.currentState?.showSnackBar(
                          SnackBar(content: Text(error.toString())));
                    }
                  }
                } else {
                  setState(() => _currentIndex = index);
                }
              },
              items: [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home),
                  label: "Home".tr(),
                ),
                BottomNavigationBarItem(
                  icon: Image.asset(
                    'assets/icons/printing.png',
                    width: isWide ? 34 : 28,
                    height: isWide ? 34 : 28,
                  ),
                  label: 'Print'.tr(),
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.tune),
                  label: 'Prepare'.tr(),
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings),
                  label: 'Settings'.tr(),
                ),
                BottomNavigationBarItem(
                  icon: Icon(
                    usbService.isConnected
                        ? Icons.usb_rounded
                        : Icons.usb_off_rounded,
                    color: usbService.isConnected ? Colors.green : Colors.red,
                  ),
                  label: usbService.isConnected
                      ? 'Connected'.tr()
                      : (usbService.isConnecting
                          ? 'Connecting'.tr()
                          : usbService.lastError != null
                              ? 'Connection_failed'.tr()
                              : 'Connect'.tr()),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
