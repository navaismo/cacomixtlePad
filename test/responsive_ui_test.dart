import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:CacomixtlePad/main.dart';
import 'package:CacomixtlePad/pages/bed_level.dart';
import 'package:CacomixtlePad/pages/extrude_retract.dart';
import 'package:CacomixtlePad/pages/home_page.dart';
import 'package:CacomixtlePad/pages/material_values.dart';
import 'package:CacomixtlePad/pages/prepare_page.dart';
import 'package:CacomixtlePad/pages/print_job.dart';
import 'package:CacomixtlePad/pages/print_page.dart';
import 'package:CacomixtlePad/pages/settings_page.dart';
import 'package:CacomixtlePad/services/gcode_repository.dart';
import 'package:CacomixtlePad/services/print_job_service.dart';
import 'package:CacomixtlePad/services/temp_svc.dart';
import 'package:CacomixtlePad/services/usb_connection_service.dart';
import 'package:CacomixtlePad/widgets/number_input_dialog.dart';
import 'package:CacomixtlePad/widgets/bed_mesh.dart';
import 'package:CacomixtlePad/widgets/responsive_layout.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_printer.dart';

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Repository extends GcodeRepository {
  _Repository() : super(requestAccess: () async => false);
  @override
  Future<List<GcodeMetadata>> list() async => [
        const GcodeMetadata(
            name: 'a_long_filename_for_a_small_phone_screen_123456789.gcode',
            totalLayers: 12345,
            estimatedTime: '12h 34m 56s'),
      ];
}

class _Printer extends FakePrinter {
  _Printer() {
    connected = false;
  }
  int gridReads = 0;
  int probes = 0;
  Completer<Map<GridPoint, double>>? gridGate;
  Completer<bool>? probeGate;
  Map<GridPoint, double> gridValues = {
    GridPoint(0, 0): -0.1,
    GridPoint(1, 0): 0.2,
    GridPoint(0, 1): 0.05,
    GridPoint(1, 1): 0.1,
  };
  @override
  Future<Map<GridPoint, double>> getBLGrid(BuildContext context) async {
    gridReads++;
    return gridGate?.future ?? Future.value(gridValues);
  }

  @override
  Future<bool> startBL(BuildContext context) async {
    probes++;
    return probeGate?.future ?? Future.value(true);
  }

  @override
  Future<Map<String, String?>> getFWInfo(BuildContext context) async => {
        'Source_Code': 'https://example.test/very/long/firmware/source/path',
        'Firmware': 'Long firmware description for a small display',
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.enableLevels = EasyLocalization.logger.enableLevels
      .where((level) => !{'debug', 'info'}.contains(level.name))
      .toList();
  late _Repository repository;
  late _Printer printer;
  late TemperatureService temperature;
  late PrintJobService job;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    repository = _Repository();
    printer = _Printer();
    temperature = TemperatureService(printer);
    job = PrintJobService(printer, repository);
  });

  tearDown(() {
    temperature.dispose();
    job.dispose();
    printer.dispose();
    repository.dispose();
  });

  Future<void> mount(WidgetTester tester, Widget page,
      {Size size = const Size(568, 320),
      double scale = 1,
      Locale locale = const Locale('en'),
      bool shell = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(EasyLocalization(
      key: UniqueKey(),
      supportedLocales: const [Locale('en'), Locale('de'), Locale('es')],
      startLocale: locale,
      saveLocale: false,
      path: 'assets/lang',
      assetLoader: const _Translations(),
      child: MultiProvider(
          providers: [
            ChangeNotifierProvider<UsbConnectionService>.value(value: printer),
            ChangeNotifierProvider<GcodeRepository>.value(value: repository),
            ChangeNotifierProvider<TemperatureService>.value(
                value: temperature),
            ChangeNotifierProvider<PrintJobService>.value(value: job),
          ],
          child: Builder(builder: (context) {
            if (shell) return page;
            return MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              theme: ThemeData.dark(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(body: page),
            );
          })),
    ));
    await tester.pumpAndSettle();
  }

  final pages = <String, Widget Function()>{
    'home': () => const HomePage(
        apiUrl: 'http://192.168.100.100:8888/uploads',
        slicerUrl: 'http://192.168.100.100:8888',
        apiKey: 'test-key'),
    'prepare': () => const PreparePage(),
    'extrusion': () => const ExtrudeRetractPage(),
    'materials': () => const MaterialValuesPage(),
    'library': () => const PrintPage(),
    'job': () => const PrintJobPage(
        filename: 'a_long_filename_for_a_small_phone_screen_123456789.gcode',
        thumbnailBase64: null,
        totalLayers: 12345,
        totalTime: '12h 34m 56s'),
    'settings': () => const SettingsPage(),
    'mesh': () => const BedLevelPage(),
  };

  for (final entry in pages.entries) {
    for (final size in [
      const Size(480, 240),
      const Size(568, 320),
      const Size(320, 568),
      const Size(1024, 600)
    ]) {
      testWidgets('${entry.key} fits $size and remains scrollable',
          (tester) async {
        await mount(tester, entry.value(), size: size);
        expect(tester.takeException(), isNull);
        final scrollable = find.byType(Scrollable).first;
        await tester.drag(scrollable, const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
    testWidgets('${entry.key} supports enlarged German text', (tester) async {
      await mount(tester, entry.value(),
          scale: 1.8, locale: const Locale('de'));
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -800));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'mesh points show their measured value and both views remain reachable',
      (tester) async {
    await mount(tester, const BedLevelPage());
    final point = find.byKey(const ValueKey('mesh-0-0'));
    await tester.ensureVisible(point);
    await tester.tap(point);
    await tester.pumpAndSettle();
    expect(find.text('X0 · Y0 · -0.100 mm'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('mesh-0-1'))).dy,
        lessThan(tester.getTopLeft(point).dy));
    await tester.ensureVisible(find.text('3D surface'));
    await tester.tap(find.text('3D surface'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mesh-selection')), findsNothing);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('+0.300 mm'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a failed refresh preserves the mesh and blocks duplicate requests',
      (tester) async {
    printer.connected = true;
    await mount(tester, const BedLevelPage());
    printer.gridGate = Completer();
    await tester.pump();
    await tester.tap(find.text('3D surface'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Get Grid'));
    await tester.tap(find.text('Get Grid'));
    await tester.pump();
    expect(printer.gridReads, 2);
    expect(printer.probes, 0);
    final controls = tester.widgetList<ControlCard>(find.byType(ControlCard));
    expect(controls.every((control) => !control.enabled), isTrue);
    printer.gridGate!.complete({});
    await tester.pumpAndSettle();
    expect(find.byType(BedMesh), findsOneWidget);
    expect(find.text('Bed Leveling Failed'), findsOneWidget);
    printer.gridGate = null;
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(printer.gridReads, 3);
    expect(find.text('Bed Leveling Failed'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'probing keeps controls disabled until the refreshed mesh is read',
      (tester) async {
    printer.connected = true;
    await mount(tester, const BedLevelPage());
    printer.probeGate = Completer();
    await tester.tap(find.text('3D surface'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Start a New Bed Level'));
    await tester.tap(find.text('Start a New Bed Level'));
    await tester.pump();
    expect(printer.probes, 1);
    expect(
        tester
            .widgetList<ControlCard>(find.byType(ControlCard))
            .every((c) => !c.enabled),
        isTrue);
    printer.gridGate = Completer();
    printer.probeGate!.complete(true);
    await tester.pump();
    expect(printer.gridReads, 2);
    expect(
        tester
            .widgetList<ControlCard>(find.byType(ControlCard))
            .every((c) => !c.enabled),
        isTrue);
    printer.gridGate!.complete({
      GridPoint(0, 0): 0,
      GridPoint(1, 0): 0,
      GridPoint(0, 1): 0,
      GridPoint(1, 1): 0
    });
    await tester.pumpAndSettle();
    expect(find.text('0.000 mm'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('numeric form actions stay above the landscape keyboard',
      (tester) async {
    double? submitted;
    await mount(
        tester,
        Builder(
            builder: (context) => Center(
                  child: ElevatedButton(
                      onPressed: () async {
                        submitted = await showNumberInputDialog(context,
                            title: 'Set Z Offset (-2.00 to +2.00)',
                            hint: 'e.g. -1.25',
                            minimum: -2,
                            maximum: 2);
                      },
                      child: const Text('Open')),
                )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final field = find.byType(EditableText);
    expect(field.hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(field).dy, greaterThanOrEqualTo(0));
    expect(tester.getBottomRight(field).dy, lessThanOrEqualTo(140));
    final confirm = find.widgetWithText(FilledButton, 'OK');
    expect(tester.getBottomRight(confirm).dy, lessThanOrEqualTo(140));
    await tester.enterText(find.byType(TextFormField), '-3');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('Invalid value'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextFormField), '-1.25');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(submitted, -1.25);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('preset fields and save remain reachable with a keyboard',
      (tester) async {
    await mount(tester, const MaterialValuesPage());
    final first = find.byType(TextFormField).first;
    await tester.tap(first);
    tester.view.viewInsets = const FakeViewPadding(bottom: 160);
    await tester.pumpAndSettle();
    await tester.enterText(first, '225');
    final save = find.byWidgetPredicate((widget) => widget is ElevatedButton);
    expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(160));
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
        (await SharedPreferences.getInstance()).getDouble('hotend_PLA'), 225);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('home temperature entry submits through the shared dialog',
      (tester) async {
    await mount(tester, pages['home']!());
    await tester.tap(find.textContaining('Hotend\n'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '215');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(printer.sent, ['M104 S215.0']);
    printer.respond();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final name in ['home', 'extrusion']) {
    testWidgets('$name movement retains its existing command sequence',
        (tester) async {
      await mount(tester, pages[name]!());
      final up = find.byIcon(Icons.keyboard_arrow_up);
      await tester.ensureVisible(up);
      await tester.tap(up);
      await tester.pump();
      expect(printer.sent, ['G91']);
      await tester.runAsync(() async {
        printer.respond();
        await until(() => printer.sent.length == 2);
        expect(printer.sent.last,
            name == 'home' ? 'G0 Y-10 F3000' : 'G0 Y10 F3000');
        printer.respond();
        await until(() => printer.sent.length == 3);
        expect(printer.sent.last, 'G90');
        printer.respond();
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('settings details scroll on a small screen', (tester) async {
    await mount(tester, const SettingsPage());
    await tester.ensureVisible(find.text('Printer Info'));
    await tester.tap(find.text('Printer Info'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('About App'));
    await tester.tap(find.text('About App'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(
        find.byType(SingleChildScrollView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('compact navigation supports enlarged translated labels',
      (tester) async {
    await mount(tester, const PrinterApp(),
        shell: true,
        size: const Size(480, 240),
        scale: 1.8,
        locale: const Locale('de'));
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('navigation releases space when the keyboard opens',
      (tester) async {
    await mount(tester, const PrinterApp(), shell: true);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    await tester.pumpAndSettle();
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
