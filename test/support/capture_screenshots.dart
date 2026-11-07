// Opt-in documentation renderer. Run with flutter test, never through app main().
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:CacomixtlePad/main.dart';
import 'package:CacomixtlePad/pages/bed_level.dart';
import 'package:CacomixtlePad/pages/extrude_retract.dart';
import 'package:CacomixtlePad/pages/home_page.dart';
import 'package:CacomixtlePad/pages/prepare_page.dart';
import 'package:CacomixtlePad/pages/print_job.dart';
import 'package:CacomixtlePad/pages/print_page.dart';
import 'package:CacomixtlePad/pages/settings_page.dart';
import 'package:CacomixtlePad/services/gcode_repository.dart';
import 'package:CacomixtlePad/services/print_job_service.dart';
import 'package:CacomixtlePad/services/temp_svc.dart';
import 'package:CacomixtlePad/services/usb_connection_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

// No UsbPort or serial protocol is created by this fixture.
class _PreviewPrinter extends UsbConnectionService {
  bool connected = false;
  @override
  bool get isConnected => connected;
  @override
  bool get isIdle => true;
  @override
  Stream<String> get lines => const Stream.empty();
  @override
  Future<List<String>> execute(String command,
          {bool fromPrint = false}) async =>
      ['ok'];
  @override
  Future<Map<GridPoint, double>> getBLGrid(BuildContext context) async {
    const heights = [
      [-0.12, -0.07, -0.03, 0.01],
      [-0.08, -0.03, 0.00, 0.04],
      [-0.04, 0.00, 0.04, 0.08],
      [0.00, 0.04, 0.08, 0.13],
    ];
    return {
      for (var y = 0; y < 4; y++)
        for (var x = 0; x < 4; x++) GridPoint(x, y): heights[y][x]
    };
  }
}

class _PreviewRepository extends GcodeRepository {
  final List<GcodeMetadata> samples;
  _PreviewRepository(this.samples) : super(requestAccess: () async => false);
  // Keep PrinterApp's upload-server startup pending: captures open no sockets.
  @override
  Future<void> ensureReady() => Completer<void>().future;
  @override
  Future<List<GcodeMetadata>> list() async => samples;
}

Future<void> _loadFonts() async {
  const configured = String.fromEnvironment('SCREENSHOT_FONT_DIR');
  final candidates = <String>[if (configured.isNotEmpty) configured];
  for (final sdk in [
    Platform.environment['ANDROID_SDK_ROOT'],
    Platform.environment['ANDROID_HOME'],
    '${Platform.environment['HOME']}/Android/Sdk',
  ].whereType<String>()) {
    final platforms = Directory('$sdk/platforms');
    if (platforms.existsSync()) {
      final installed = platforms.listSync().whereType<Directory>().toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      candidates.addAll(installed.map((p) => '${p.path}/data/fonts'));
    }
  }
  final fontDir = candidates.firstWhere(
    (path) => File('$path/Roboto-Regular.ttf').existsSync(),
    orElse: () => throw StateError('Install Android SDK Roboto fonts or pass '
        '--dart-define=SCREENSHOT_FONT_DIR=/path/to/fonts'),
  );
  final roboto = FontLoader('Roboto');
  for (final face in ['Regular', 'Medium', 'Bold']) {
    roboto.addFont(Future.value(ByteData.sublistView(
        File('$fontDir/Roboto-$face.ttf').readAsBytesSync())));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
}

// A small, synthetic calibration cube used only as example G-code metadata.
Future<String> _cubeThumbnail(Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  void face(List<Offset> points, Color fill) {
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(path, Paint()..color = fill);
  }

  canvas.drawOval(const Rect.fromLTWH(32, 186, 196, 35),
      Paint()..color = const Color(0x33181a21));
  const top = Offset(128, 25), left = Offset(44, 67), right = Offset(212, 67);
  const middle = Offset(128, 111), bottom = Offset(128, 220);
  face([left, middle, bottom, const Offset(44, 176)],
      Color.lerp(color, Colors.black, 0.18)!);
  face([middle, right, const Offset(212, 176), bottom],
      Color.lerp(color, Colors.black, 0.38)!);
  face([top, right, middle, left], Color.lerp(color, Colors.white, 0.24)!);
  final lines = Paint()
    ..color = Colors.white.withValues(alpha: 0.14)
    ..strokeWidth = 1;
  for (var i = 1; i < 18; i++) {
    final dy = i * 6.0;
    canvas.drawLine(Offset(44, 67 + dy), Offset(128, 111 + dy), lines);
    canvas.drawLine(Offset(128, 111 + dy), Offset(212, 67 + dy), lines);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 256);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return base64Encode(png!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('render current screens for the README without hardware',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync())!
        .group(1)!;
    PackageInfo.setMockInitialValues(
        appName: 'CacomixtlePad',
        packageName: 'CacomixtlePad',
        version: version.split('+').first,
        buildNumber: '1',
        buildSignature: 'preview');
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableLevels = [];
    await _loadFonts();
    WidgetsApp.debugAllowBannerOverride = false;
    addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
    final samples = <GcodeMetadata>[];
    await tester.runAsync(() async {
      final models = <String, Color>{
        'cube_PLA.gcode': const Color(0xff66cfce),
        'cube_PETG.gcode': const Color(0xfff4ae83),
        'cube_TPU.gcode': const Color(0xffa6a3e9),
      };
      for (final entry in models.entries) {
        samples.add(GcodeMetadata(
            name: entry.key,
            thumbnailBase64: await _cubeThumbnail(entry.value),
            totalLayers: 100,
            estimatedTime: '41m'));
      }
    });
    final printer = _PreviewPrinter();
    final repository = _PreviewRepository(samples);
    final temperature = TemperatureService(printer);
    printer.connected = true;
    temperature.hotendTemp = '205.0';
    temperature.targetHotend = 205;
    temperature.bedTemp = '60.0';
    temperature.targetBed = 60;
    temperature.fanSpeed = 180;
    final job = PrintJobService(printer, repository);
    await job.ready;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(() {
      temperature.dispose();
      job.dispose();
      printer.dispose();
      repository.dispose();
    });
    const boundaryKey = ValueKey('readme-capture');

    Future<void> mount(Widget page,
        {Size size = const Size(1024, 480), bool shell = false}) async {
      tester.view.physicalSize = size;
      tester.view.resetViewInsets();
      await tester.pumpWidget(EasyLocalization(
        key: UniqueKey(),
        supportedLocales: const [Locale('en')],
        startLocale: const Locale('en'),
        saveLocale: false,
        path: 'assets/lang',
        assetLoader: const _Translations(),
        child: MultiProvider(
            providers: [
              ChangeNotifierProvider<UsbConnectionService>.value(
                  value: printer),
              ChangeNotifierProvider<GcodeRepository>.value(value: repository),
              ChangeNotifierProvider<TemperatureService>.value(
                  value: temperature),
              ChangeNotifierProvider<PrintJobService>.value(value: job),
            ],
            child: RepaintBoundary(
                key: boundaryKey,
                child: shell
                    ? page
                    : Builder(
                        builder: (context) => MaterialApp(
                              debugShowCheckedModeBanner: false,
                              locale: context.locale,
                              supportedLocales: context.supportedLocales,
                              localizationsDelegates:
                                  context.localizationDelegates,
                              theme: ThemeData.dark().copyWith(
                                  elevatedButtonTheme: ElevatedButtonThemeData(
                                      style: ElevatedButton.styleFrom(
                                          minimumSize: const Size(48, 48))),
                                  filledButtonTheme: FilledButtonThemeData(
                                      style: FilledButton.styleFrom(
                                          minimumSize: const Size(48, 48)))),
                              home: Scaffold(body: page),
                            )))),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      // Resolve actual image frames before capturing; pumpAndSettle alone may finish before image IO.
      final imageWidgets = tester.widgetList<Image>(find.byType(Image));
      await tester.runAsync(() async {
        for (final widget in imageWidgets) {
          await precacheImage(
              widget.image, tester.element(find.byType(Image).first));
        }
      });
      await tester.pumpAndSettle();
      // Match Android's default for familyless text. The headless test engine
      // otherwise substitutes square test glyphs, even with Roboto loaded.
      for (final element in find.byType(RichText).evaluate()) {
        final paragraph = element.renderObject! as RenderParagraph;
        final span = paragraph.text;
        if (span is TextSpan && span.style?.fontFamily == null) {
          paragraph.text = TextSpan(
              text: span.text,
              children: span.children,
              style: (span.style ?? const TextStyle())
                  .copyWith(fontFamily: 'Roboto'));
        }
      }
      await tester.pump();
      expect(tester.takeException(), isNull, reason: name);
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('extras/screenshots').create(recursive: true);
        await File('extras/screenshots/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await mount(const HomePage(
        apiUrl: 'http://192.0.2.10:8888/uploads',
        slicerUrl: 'http://192.0.2.10:8888',
        apiKey: 'EXAMPLE-ONLY'));
    await capture('home');
    await tester.tap(find.textContaining('Hotend\n'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '210');
    await capture('temperature-form');

    await mount(const PrintPage());
    await capture('library');
    job.metadata = samples.first;
    job.state = PrintState.printing;
    job.progress = 42;
    job.currentLayer = 42;
    job.remainingMinutes = 24;
    job.elapsed = const Duration(minutes: 17);
    printer.printActive = repository.locked = true;
    final printPage = PrintJobPage(
        filename: samples.first.name,
        thumbnailBase64: samples.first.thumbnailBase64,
        totalLayers: samples.first.totalLayers,
        totalTime: samples.first.estimatedTime);
    await mount(printPage);
    await capture('printing');
    job.state = PrintState.paused;
    printer.pauseMotionActive = true;
    await mount(printPage);
    await capture('paused');
    await mount(const PrinterApp(), shell: true);
    await tester.tap(find.text('Prepare').last);
    await tester.pumpAndSettle();
    await capture('active-print');
    await tester.pumpWidget(const SizedBox());
    job.state = PrintState.idle;
    job.metadata = null;
    printer.printActive = printer.pauseMotionActive = repository.locked = false;

    await mount(const PreparePage());
    await capture('prepare');
    await tester.tap(find.text('Z Offset'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '-1.45');
    await capture('z-offset-form');
    await mount(const PreparePage());
    await tester.tap(find.text('Disable Motors'));
    await tester.pumpAndSettle();
    await capture('motors-dialog');

    await mount(const ExtrudeRetractPage());
    await tester.tap(find.text('200°C'));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('50mm'));
    await tester.pumpAndSettle();
    await capture('extrusion');

    await mount(const BedLevelPage(), size: const Size(1024, 720));
    await tester.tap(find.byKey(const ValueKey('mesh-2-1')));
    await tester.pumpAndSettle();
    await capture('mesh-height-map');
    await tester.tap(find.text('3D surface'));
    await tester.pumpAndSettle();
    await capture('mesh-surface');

    await mount(const SettingsPage());
    await capture('settings');
    tester.view.physicalSize = const Size(1024, 780);
    await tester.tap(find.text('Edit Material Values'));
    await tester.pumpAndSettle();
    await capture('materials');

    await mount(const PreparePage(), size: const Size(568, 320));
    await tester.tap(find.text('Z Offset'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '-1.45');
    await capture('compact-form');
    await tester.pumpWidget(const SizedBox());
  });
}
