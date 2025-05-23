import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'pages/home_page.dart';
import 'package:shelf/shelf.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_multipart/multipart.dart';
import 'package:shelf_multipart/form_data.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'pages/prepare_page.dart';
import 'pages/print_page.dart';
import 'pages/settings_page.dart';
import 'services/temp_svc.dart';
import 'services/usbConn_svc.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  WakelockPlus.enable();

  runApp(
    EasyLocalization(
      startLocale: Locale.fromSubtags(languageCode: 'en'),
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
      fallbackLocale: Locale('en', 'US'),
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => TemperatureService()),
          ChangeNotifierProvider(create: (_) => UsbConnectionService()),
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
  List<GcodeMetadata> gcodeFiles = [];
  HttpServer? _server;
  String? localIp;
  String API_URL = '';
  String Slicer_URL = '';
  int API_Port = 8888;

  @override
  void dispose() {
    Provider.of<TemperatureService>(context, listen: false).stop();
    Provider.of<UsbConnectionService>(context, listen: false).disposeService();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _ensureGcodeFolder().then((_) {
      _startUploadServer();
      _getLocalIpAddress();
    });
  }

  Future<String?> _getLocalIpAddress() async {
    final NetworkInfo networkInfo = NetworkInfo();
    try {
      String? ip = await networkInfo.getWifiIP();
      localIp = ip ?? '0.0.0.0';
      setState(() {});
      return localIp;
    } catch (e) {
      print('Error getting local IP: $e');
      return '0.0.0.0';
    }
  }

  Future<String> _getExternalGcodeDirectory() async {
    final dir = Directory('/storage/emulated/0/Download/gcode_files');
    if (!(await dir.exists())) await dir.create(recursive: true);
    return dir.path;
  }

  Future<void> _ensureGcodeFolder() async {
    if (!await Permission.manageExternalStorage.request().isGranted) {
      print("Permission_denied".tr());
    } else {
      await _getExternalGcodeDirectory();
    }
  }

  Future<void> _startUploadServer() async {
    final handler = (Request request) async {
      if (request.method == 'POST' &&
          (request.url.path == 'uploads' ||
              request.url.path == 'api/files/local')) {
        if (request.isMultipart && request.isMultipartForm) {
          final formDataList = await request.multipartFormData.toList();

          for (final formData in formDataList) {
            final filename = formData.filename;
            if (filename != null) {
              final targetPath =
                  path.join(await _getExternalGcodeDirectory(), filename);
              final file = File(targetPath);
              final sink = file.openWrite();
              await formData.part.pipe(sink);
              await sink.close();
            }
          }
        } else {
          return Response.badRequest(body: 'Not a multipart/form-data Request');
        }
        return Response.ok('File(s) uploaded successfully');
      } else if (request.method == 'GET' && request.url.path == 'api/version') {
        final apires = {
          "api": "0.1",
          "server": "1.11.1",
          "text": "OctoPrint 1.11.1",
        };

        return Response.ok(jsonEncode(apires),
            headers: {'Content-Type': 'application/json'});
      } else if (request.method == 'GET' &&
          request.url.path == 'api/settings') {
        final settings = {
          "accessControl": {
            "autologinHeadsupAcknowledged": false,
            "autologinLocal": false
          },
          "api": {"allowCrossOrigin": false, "key": null}
        };
        return Response.ok(jsonEncode(settings),
            headers: {'Content-Type': 'application/json'});
      }

      return Response.notFound('Path_not_found'.tr());
    };

    final ip = await _getLocalIpAddress();
    _server = await shelf_io.serve(
      logRequests().addHandler(handler),
      InternetAddress(ip ?? '0.0.0.0'),
      API_Port,
    );

    print('Server ready: http://$ip:${_server!.port}/uploads');
    setState(() {
      API_URL = 'http://$ip:$API_Port/uploads';
      Slicer_URL = 'http://$ip:$API_Port';
    });
  }

  @override
  Widget build(BuildContext context) {
    final usbService = Provider.of<UsbConnectionService>(context);
    final tempService = Provider.of<TemperatureService>(context);

    print(context.locale);
    print(tr('Home'));

    if (usbService.port != null && usbService.isConnected) {
      tempService.start(usbService.port!);
    }

    final screen = MediaQuery.of(context).size;
    final isWide = screen.width > 1000;

    final pages = [
      HomePage(
        API_URL: API_URL,
        Slicer_URL: Slicer_URL,
      ),
      const PrintPage(),
      const PreparePage(),
      const SettingsPage(),
    ];

    return MaterialApp(
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      title: 'Cacomixtle-Pad',
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return pages[_currentIndex];
            },
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.only(bottom: 15.0),
          child: Container(
            height: isWide ? 80 : 60,
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              iconSize: isWide ? 34 : 28,
              selectedFontSize: isWide ? 18 : 16,
              unselectedFontSize: isWide ? 16 : 14,
              currentIndex: _currentIndex,
              onTap: (index) {
                if (index == 4) {
                  usbService.connect();
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
                      : 'Connect'.tr(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
