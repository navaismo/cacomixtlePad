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
import 'pages/print_job.dart';
import 'pages/settings_page.dart';
import 'services/temp_svc.dart';
import 'services/usb_connection_service.dart';

class _PrintRouteObserver extends NavigatorObserver {
  final _routes = <Route<dynamic>>[];
  bool get hasPrintJob =>
      _routes.any((route) => route.settings.name == PrintJobPage.routeName);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute == null) return;
    final index = _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
  }
}

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
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _routes = _PrintRouteObserver();
  PrintJobService? _job;
  bool _wasCancelling = false;
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
    _job?.removeListener(_onJobChanged);
    _server?.close(force: true);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final job = context.read<PrintJobService>();
    if (_job != job) {
      _job?.removeListener(_onJobChanged);
      _job = job;
      _wasCancelling = false;
      job.addListener(_onJobChanged);
    }
  }

  void _onJobChanged() {
    final job = _job!;
    if (job.state == PrintState.cancelling) _wasCancelling = true;
    if (_wasCancelling && job.state == PrintState.cancelled && !job.isActive) {
      _wasCancelling = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || job.state != PrintState.cancelled) return;
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
        setState(() => _currentIndex = 0);
        if (job.error != null) {
          _messenger.currentState
              ?.showSnackBar(SnackBar(content: Text(job.error!.tr())));
        }
      });
    } else if (_wasCancelling &&
        job.state == PrintState.failed &&
        !job.isActive) {
      _wasCancelling = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || job.state != PrintState.failed || job.error == null) {
          return;
        }
        _messenger.currentState
            ?.showSnackBar(SnackBar(content: Text(job.error!.tr())));
      });
    } else if (job.state == PrintState.completed && !job.isActive) {
      _wasCancelling = false;
    }
  }

  void _openActivePrint(GcodeMetadata metadata) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    if (_routes.hasPrintJob) {
      navigator
          .popUntil((route) => route.settings.name == PrintJobPage.routeName);
      return;
    }
    navigator.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: PrintJobPage.routeName),
      builder: (_) => PrintJobPage(
        filename: metadata.name,
        thumbnailBase64: metadata.thumbnailBase64,
        totalLayers: metadata.totalLayers,
        totalTime: metadata.estimatedTime,
      ),
    ));
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
      navigatorKey: _navigatorKey,
      navigatorObservers: [_routes],
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
      builder: (context, child) => Column(children: [
        Selector<PrintJobService, GcodeMetadata?>(
          selector: (_, job) => job.isActive ? job.metadata : null,
          builder: (context, metadata, _) => metadata == null
              ? const SizedBox.shrink()
              : SafeArea(
                  bottom: false,
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('active-print-button'),
                      onPressed: () => _openActivePrint(metadata),
                      icon: const Icon(Icons.print_rounded),
                      label: Text('Active_print'.tr(),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        textStyle: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
        ),
        Expanded(child: child ?? const SizedBox.shrink()),
      ]),
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
