import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:CacomixtlePad/widgets/gcode_thumbnail.dart';

const thumbnailPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGOw2XICAALoAblAcHO8AAAAAElFTkSuQmCC';
const otherThumbnailPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGM4EWADAAM4AVWTKi8tAAAAAElFTkSuQmCC';

void main() {
  testWidgets(
      'updates keep the provider and visible frame for an unchanged thumbnail',
      (tester) async {
    final progress = ValueNotifier(0);
    addTearDown(progress.dispose);
    await tester.pumpWidget(MaterialApp(
        home: ValueListenableBuilder<int>(
      valueListenable: progress,
      builder: (_, value, __) => Column(children: [
        Text('$value%'),
        const GcodeThumbnail(base64: thumbnailPng, height: 140),
      ]),
    )));
    await tester.pumpAndSettle();
    final provider = tester.widget<Image>(find.byType(Image)).image;
    await tester.runAsync(
        () => precacheImage(provider, tester.element(find.byType(Image))));
    await tester.pumpAndSettle();
    final frame = tester.widget<RawImage>(find.byType(RawImage)).image;
    expect(frame, isNotNull);
    for (var value = 1; value <= 20; value++) {
      progress.value = value;
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<Image>(find.byType(Image)).image, same(provider));
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(frame));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a different payload invalidates the provider; invalid Base64 shows a fallback',
      (tester) async {
    Future<void> show(String? base64) async {
      await tester
          .pumpWidget(MaterialApp(home: GcodeThumbnail(base64: base64)));
      await tester.pumpAndSettle();
    }

    await show(thumbnailPng);
    final provider = tester.widget<Image>(find.byType(Image)).image;
    await show(otherThumbnailPng);
    expect(
        tester.widget<Image>(find.byType(Image)).image, isNot(same(provider)));
    await show('invalid!');
    expect(find.byIcon(Icons.insert_drive_file), findsOneWidget);
    await show(null);
    expect(find.byIcon(Icons.insert_drive_file), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
