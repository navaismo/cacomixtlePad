# Copilot Instructions for CacomixtlePad

CacomixtlePad is a Flutter Android app that replaces the LCD interface on an Ender 3 V3 SE 3D printer via USB OTG, supporting any Marlin 2 firmware. The phone streams the print over G-code at 115200 baud, so it must remain connected and running.

## Build and test commands

Run the following in the repository root:

```bash
# Install dependencies with locked versions
flutter pub get --offline --enforce-lockfile

# Check code formatting (lib/main.dart, pages, services, widgets, and tests)
dart format --output=none --set-exit-if-changed lib/main.dart lib/pages lib/services lib/widgets test

# Static analysis
flutter analyze --no-pub

# Run all tests
flutter test --no-pub --reporter expanded

# Run a single test file
flutter test test/gcode_protocol_test.dart --no-pub

# Build debug APK
flutter build apk --debug --no-pub

# Validate release signing (requires python3 and Java 17)
python3 tool/validate_release_signing.py

# Check translation keys consistency across seven languages
python3 tool/check_translations.py
```

The CI runs on Flutter 3.29.3 with Dart `>=2.17.0 <4.0.0`, Android minSdk 21, and Java 17.

## High-level architecture

### Core communication and state
- **`GcodeProtocol`** — Owns the USB subscription, line buffer, and FIFO. One command awaits ACK at a time. Recognizes `ok` as a complete line.
- **`UsbConnectionService`** — Manages USB 115200/8N1 connection, handshake, DTR/RTS, and validates manual commands during printing. Routes all commands through `GcodeProtocol.execute()`.
- **`GcodeRepository`** — Manages the `/storage/emulated/0/Download/gcode_files` directory, permissions, metadata, thumbnails, and upload/deletion with write locking.

### Print job orchestration
- **`PrintJobService`** — Shared across all routes (outside navigation). Streams G-code lines, manages pause/resume/cancel, and coordinates with `TemperatureService` and `PauseParking`.
- **`PrintJobStore`** — Persists the last job record to SharedPreferences before the first send, every 5 seconds, and on pause/resume/cancel/completion. On restart, marks interrupted jobs as interrupted (does not auto-resume).
- **`PauseParking`** — Drains accepted moves, verifies homing/position/soft-limits via `M114`/`M211`, lifts Z up to 30 mm, and parks at Y maximum minus 5 mm. Resume restores XY, then Z, and verifies position before proceeding.

### User interface and other services
- **`TemperatureService`** — Polls `M105` (at most one pending) with a 10-second inactivity timeout and 30-minute absolute limit per command. Manages hotend, bed, and fan.
- **`MaterialPresets`** — Reads hotend/bed temperatures for PLA, PETG, TPU, ABS (validated on load).
- **`UploadApi`** — Shelf HTTP server on port 8888. Routes:
  - `POST /uploads` and `POST /api/files/local` (require `X-Api-Key` header)
  - `GET /api/version` and `GET /api/settings` (public, no key needed)
  - Supports OrcaSlicer and Cura metadata, Base64 thumbnails, and `M73` progress
  - Uploads are blocked during active print jobs; existing names return 409

### Pages and widgets
- **`lib/pages/`** — Home (movement, temps), Print library, Printing (job controls), Prepare (Z offset, extrude, bed mesh), Settings, Material presets.
- **`lib/widgets/`** — Responsive layouts, control cards, numeric forms with keyboard awareness, bed mesh selection, stable thumbnail display.

### Localization and configuration
- **`assets/lang/`** — Seven languages (en, es, ru, fr, de, it, pt), 110 keys each. Selection persists; no forced English.
- **`android/key.prop`** — Release signing key (created interactively, never committed). Temporary keys are for validation only.

## Key conventions

### Package name and imports
- The Dart package name is **`CacomixtlePad`** (capital C, case-sensitive). Preserve this capitalization in imports.

### USB and printer communication
- Every command must route through `UsbConnectionService.execute()` and `GcodeProtocol`. Do not add direct port writes or USB listeners to screens.
- Debug builds also control real hardware; there is no automatic simulation. Tests explicitly mock the transport layer.
- The app initializes with `M110 N0`, `M105` confirmation, then `G21`, `G90`, `M82`, `M84 S120` before announcing connection.
- Motor idle timeout starts at 120 seconds; it is restored after pause/resume cycles.

### Print job and state persistence
- Keep the print job in `PrintJobService`, outside navigation routes, so printing continues when switching screens.
- The persisted record in `PrintJobStore` identifies interrupted jobs but does not authorize automatic resuming. On restart, the app restores the last job record and marks it as interrupted.
- Resend validation: allow up to three identical retries on `Resend` for the pending line. Do not advance the print on transport ACK; only advance on command ACK.
- Avoid resending movements that have already been acknowledged.

### UI and responsive design
- Use available layout constraints and text scaling for small viewports.
- Keep controls scrollable and touchable, checking behavior with keyboard insets.
- The app uses landscape orientation, dark theme, immersive mode, and wakelock.

### Translatable text
- Keep all translatable strings in `assets/lang/` JSON files.
- Maintain the keys across all seven languages (en, es, ru, fr, de, it, pt).
- The language selection persists in SharedPreferences and is restored on app restart.

### Upload routes and API compatibility
- Preserve `X-Api-Key` header authentication unless changing the upload mechanism.
- Maintain OctoPrint compatibility routes (`/uploads`, `/api/files/local`, `/api/version`, `/api/settings`).
- Existing filenames return HTTP 409; rename or delete the old file first.
- Upload limits: 256 MiB per file, 512 MiB per request.

### License and documentation
- This project uses the **AGPL-3.0-only** license.
- Write all documentation in English, using direct instructions and "we" for shared decisions.
- Do not commit credentials or signing keys. Create keys interactively and use temporary certificates only for validation.

### Before editing
- Run `git status --short` to see what's already changed.
- Keep your changes within the task's scope.
- Run analysis and relevant tests after making changes.
- For Android-specific changes, build the debug APK when the environment allows.
- Update [MEMORY.md](MEMORY.md) if architecture, commands, or outstanding work changes.

## Reference documentation

- **[MEMORY.md](MEMORY.md)** — Current architecture, contracts, and behavior details. Start here.
- **[README.md](README.md)** — Installation, features, connection setup, and slicer integration.
- **[PRINTING_AND_MESH.md](docs/PRINTING_AND_MESH.md)** — Pause/resume prerequisites, homing, position/limit verification, and bed mesh behavior.
- **[RELEASE.md](docs/RELEASE.md)** — Development and release build signing.
