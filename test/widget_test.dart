import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:CacomixtlePad/pages/material_values.dart';
import 'package:CacomixtlePad/pages/print_page.dart';
import 'package:CacomixtlePad/pages/print_job.dart';
import 'package:CacomixtlePad/services/gcode_repository.dart';
import 'package:CacomixtlePad/services/print_job_service.dart';
import 'package:CacomixtlePad/services/temp_svc.dart';
import 'package:CacomixtlePad/services/usb_connection_service.dart';
import 'support/fake_printer.dart';
import 'thumbnail_test.dart' show thumbnailPng;

class _Translations extends AssetLoader {
  final Map<String, dynamic> data;
  const _Translations(this.data);
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => data;
}

class _EmptyRepository extends GcodeRepository {
  _EmptyRepository() : super(requestAccess: () async => true);
  @override
  Future<List<GcodeMetadata>> list() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final translations =
      jsonDecode(File('assets/lang/en.json').readAsStringSync())
          as Map<String, dynamic>;
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'hotend_PLA': 215.0, 'bed_PLA': 65.0});
    await EasyLocalization.ensureInitialized();
  });

  Future<void> mount(WidgetTester tester, Widget page,
      {FakePrinter? printer,
      GcodeRepository? repository,
      PrintJobService? job,
      TemperatureService? temperature}) async {
    await tester.pumpWidget(EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/lang',
        assetLoader: _Translations(translations),
        child: Builder(builder: (context) {
          Widget child = MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: page);
          if (printer != null ||
              repository != null ||
              job != null ||
              temperature != null) {
            child = MultiProvider(providers: [
              if (printer != null)
                ChangeNotifierProvider<UsbConnectionService>.value(
                    value: printer),
              if (repository != null)
                ChangeNotifierProvider<GcodeRepository>.value(
                    value: repository),
              if (job != null)
                ChangeNotifierProvider<PrintJobService>.value(value: job),
              if (temperature != null)
                ChangeNotifierProvider<TemperatureService>.value(
                    value: temperature),
            ], child: child);
          }
          return child;
        })));
    await tester.pumpAndSettle();
  }

  testWidgets('empty library exposes import without a USB connection',
      (tester) async {
    final repository = _EmptyRepository();
    final printer = FakePrinter();
    printer.connected = false;
    final job = PrintJobService(printer, repository);
    await mount(tester, const PrintPage(), repository: repository, job: job);
    expect(
        find.text('No G-code files yet. Upload one to begin.'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Upload G-code'));
    expect(button.onPressed, isNotNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
    job.dispose();
    printer.dispose();
    repository.dispose();
  });

  testWidgets('preset editor displays saved values and persists edits',
      (tester) async {
    await mount(tester, const MaterialValuesPage());
    final fields = find.byType(TextFormField);
    expect(
        tester.widget<TextFormField>(fields.at(0)).controller!.text, '215.0');
    expect(tester.widget<TextFormField>(fields.at(1)).controller!.text, '65.0');
    await tester.enterText(fields.at(0), '225');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
        (await SharedPreferences.getInstance()).getDouble('hotend_PLA'), 225.0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'print progress and temperature updates retain the decoded thumbnail',
      (tester) async {
    final directory = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('thumbnail-route-')))!;
    final repository =
        GcodeRepository(directory: directory, requestAccess: () async => true);
    final printer = FakePrinter()..connected = false;
    final temperature = TemperatureService(printer);
    printer.connected = true;
    final job = PrintJobService(printer, repository);
    await tester.runAsync(
        () => repository.file('part.gcode').writeAsString('M73 P25\nG1 X10\n'));
    await mount(
        tester,
        const PrintJobPage(
            filename: 'part.gcode',
            thumbnailBase64: thumbnailPng,
            totalLayers: 4,
            totalTime: '1m'),
        printer: printer,
        repository: repository,
        job: job,
        temperature: temperature);
    final imageFinder =
        find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage);
    final provider = tester.widget<Image>(imageFinder).image;
    Future<void>? run;
    await tester.runAsync(() async {
      run = job.start(const GcodeMetadata(
          name: 'part.gcode', totalLayers: 4, estimatedTime: '1m'));
      await until(() => printer.sent.length == 1);
    });
    printer.respond();
    await tester.pump();
    await tester.runAsync(() => until(() => printer.sent.length == 2));
    expect(job.progress, 25);
    expect(tester.widget<Image>(imageFinder).image, same(provider));
    temperature.hotendTemp = '205.0';
    temperature.notifyListeners();
    await tester.pump();
    expect(tester.widget<Image>(imageFinder).image, same(provider));
    await tester.runAsync(() async {
      printer.respond();
      await until(() => printer.sent.length == 3).catchError((Object error) {
        throw StateError(
            'Completion barrier: $error; sent=${printer.sent}; state=${job.state}; error=${job.error}');
      });
      printer.respond();
      await run;
    });
    await tester.pumpAndSettle();
    expect(tester.widget<Image>(imageFinder).image, same(provider));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    job.dispose();
    temperature.dispose();
    printer.dispose();
    repository.dispose();
    await tester.runAsync(() => directory.delete(recursive: true));
  });

  testWidgets(
      'removing the print route leaves its service and transmission alive',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final directory = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('route-test-')))!;
    final repository =
        GcodeRepository(directory: directory, requestAccess: () async => true);
    final printer = FakePrinter();
    final job = PrintJobService(printer, repository);
    printer.connected = false;
    final temperature = TemperatureService(printer);
    printer.connected = true;
    await tester.runAsync(() async {
      await repository.file('test.gcode').writeAsString('G1 X10\n');
    });
    await mount(
        tester,
        const PrintJobPage(
            filename: 'test.gcode',
            thumbnailBase64: null,
            totalLayers: 0,
            totalTime: ''),
        printer: printer,
        repository: repository,
        job: job,
        temperature: temperature);
    Future<void>? run;
    await tester.runAsync(() async {
      run = job.start(const GcodeMetadata(
          name: 'test.gcode', totalLayers: 0, estimatedTime: ''));
      await until(() => printer.sent.length == 1);
    });
    await tester.pumpWidget(const SizedBox());
    expect(job.isActive, isTrue);
    await tester.runAsync(() async {
      printer.respond();
      await until(() => printer.sent.length == 2);
      expect(printer.sent.last, 'M400');
      printer.respond();
      await run;
    });
    expect(job.state, PrintState.completed);
    temperature.dispose();
    job.dispose();
    printer.dispose();
    repository.dispose();
    await tester.runAsync(() => directory.delete(recursive: true));
  });
}
