# README screenshots

We render the current Flutter widgets with example data so you can refresh the
README without connecting a phone or printer. The images live in
`extras/screenshots/`. We captured this set on 2026-11-07 with app version 1.1.1.

## Generate the images

Run this from the repository root with the project's Flutter SDK and dependencies
already available:

```sh
flutter test --no-pub test/support/capture_screenshots.dart --reporter expanded
```

The tool uses installed Android SDK fonts, including Roboto, and the app's Material icons and assets. It looks under `ANDROID_SDK_ROOT`,
`ANDROID_HOME`, and `~/Android/Sdk`. If your SDK keeps fonts elsewhere, provide a
directory containing `Roboto-Regular.ttf`, `Roboto-Medium.ttf`, and `Roboto-Bold.ttf`:

```sh
flutter test --no-pub test/support/capture_screenshots.dart \
  --dart-define=SCREENSHOT_FONT_DIR=/path/to/android/fonts \
  --reporter expanded
```

We generate the images at 1.5× resolution, preserve their aspect ratios in the
README, and hide the debug banner. For text without an explicit font family, the
capture renderer resolves Roboto as Android does, instead of using the headless
engine’s square test glyphs. We do not change app widgets for this. The capture fixture takes the version from
`pubspec.yaml`. The opt-in command overwrites the PNGs; the normal test suite
does not regenerate documentation images.

## What we capture

| Image | Screen or state |
| --- | --- |
| `home.png` | Temperatures, API URLs, and movement controls |
| `library.png` | Example G-code files and cube thumbnails |
| `printing.png` | A print at 42% |
| `paused.png` | Resume available and Z offset disabled |
| `active-print.png` | The real app shell with the global job button and navigation |
| `prepare.png` | Preparation controls |
| `z-offset-form.png` | Global probe offset input |
| `extrusion.png` | Temperature, extrusion, and movement controls |
| `motors-dialog.png` | Motor-disable confirmation |
| `mesh-height-map.png` | A selected point in a 4 × 4 mesh |
| `mesh-surface.png` | The same mesh in 3D |
| `settings.png` | App and printer settings |
| `materials.png` | Four material presets and Save |
| `temperature-form.png` | Standard numeric form |
| `compact-form.png` | Numeric form above simulated keyboard insets |

Most captures use a 1024 × 480 logical viewport. The mesh views use 1024 × 720,
the preset editor uses 1024 × 780, and the compact form uses 568 × 320 with a
180-pixel bottom inset. The compact capture reserves space for the keyboard;
it does not draw an Android IME.

## Fixture boundaries

We use real page widgets with simulated temperatures, print progress, a selected
mesh point, and synthetic cube thumbnails. These images show supported UI states;
they do not prove printer movement or calibration. Point editing remains a
proposal, so we do not show controls that have not been implemented.

Most captures show a page directly. The global active-print example uses
`PrinterApp` itself. Its storage-readiness future stays pending to prevent the
upload server from opening a socket. The fixture creates no USB ports, overrides
command execution, and never invokes the production entry point. API addresses
and the example key are placeholders, not credentials.

We leave the earlier phone demo and slicer setup images in place. The README
labels the older demo so you can distinguish it from the current UI captures.

## Check a refresh

Inspect the rendered images for readable fonts and icons, complete dialogs,
clipping, and consistent sample state. Then run:

```sh
flutter analyze --no-pub
python3 tool/check_translations.py
git diff --check
```

We ran the capture successfully and inspected the output. These captures do not
replace phone, keyboard, OTG, or physical printer validation.
