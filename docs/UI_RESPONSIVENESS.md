# Responsive UI adjustments

We updated the Android interface to keep controls and forms usable on small
screens and when the software keyboard reduces the available height. We kept
our dark theme, existing icons, and printer command flows.

## What changed

- We added shared layout widgets in `lib/widgets/`: scrollable page content,
  columns that stack when space is limited, and control cards that grow with
  their labels. Layout decisions use local width and text scaling.
- We rebuilt the numeric input dialog around available height. With a short
  keyboard viewport, the input, cancel control, and confirmation share one row.
  With more space, we show the full title, range, and actions vertically.
  Invalid values stay in the form; you can submit valid values with the
  keyboard's Done action. The dialog owns and disposes its controller.
- We made Home prioritize temperature and movement controls on compact screens.
  Printer information and API details remain available by scrolling. We kept
  movement buttons at usable touch sizes instead of shrinking them with width.
- We made print progress, controls, extrusion choices, preparation, settings,
  and the bed mesh scrollable. Labels can wrap, and pushed screens include
  navigation back to the previous screen.
- We put library actions and file cards in one scroll view. The file grid uses
  available width and text size, while long names retain a bounded preview.
- We stack preset fields on narrow screens. The Save action stays outside the
  scrolling field list and above the keyboard through Scaffold resizing.
- We compacted the navigation bar and hide it while the keyboard is visible.
  The server error banner keeps a compact summary, with full details available
  from its information button.
- We fit the projected leveling mesh within its drawing area and reserve space
  for statistics instead of using a fixed canvas size and zoom.

## Validation

We added 48 responsive UI tests in `test/responsive_ui_test.dart`. They cover
eight screens at 480×240, 568×320, 320×568, and 1024×600 logical pixels, enlarged
German text at 1.8×, keyboard insets, input visibility and submission, preset
saving, settings dialogs, navigation, and the existing movement sequences.

Our full Flutter test suite passes 95 tests. We also reviewed temporary rendered
previews of Home, the print screen, and the numeric dialog with a simulated
keyboard inset. Those previews use test fixtures, not a physical Android device.
Static analysis reports no issues, all seven translation files retain 95 keys,
and the debug APK builds successfully at
`build/app/outputs/flutter-apk/app-debug.apk`. We included the shared widgets
in CI's formatting check.

Run the checks with:

```sh
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
python3 tool/check_translations.py
flutter build apk --debug --no-pub
```

We still need to check the keyboard behavior on the phone with its actual IME,
display scaling, and navigation insets. Our security audit remains open; these
UI changes do not resolve its upload, storage, or dependency findings.
