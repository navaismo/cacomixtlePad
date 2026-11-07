# CacomixtlePad memory

We started this memory on 2026-11-07 at `9f7a9e1` and updated it with two rounds
of fixes that day. The fixes, security review, and responsive UI work are now
committed in `a05dc87`. Later printing, mesh, and version changes were also
committed before our screenshot refresh, which started at `807adee`.
The [initial analysis](docs/REPO_ANALYSIS.md) is historical; the current status
and validation of the fixes are in the reports for the
[first round](docs/FIXES_2026-11-07.md) and
[second round](docs/FIXES_2026-11-07_2.md).

## Product and agreed scope

Our Flutter Android app, version `1.1.1`, replaces LCD functions on an Ender
3 V3 SE through USB OTG and G-code at 115200 baud. The README describes
compatibility with other Marlin 2 printers as a possibility; we have not
verified it in this session. The interface uses landscape orientation, a dark
theme, immersive mode, and wakelock.

The phone streams the print: it needs power and a running process. Printing
continues when you leave a screen. If the process dies, reopening the app
restores the last job record and marks it as interrupted; movements do not
resume automatically.

The screens cover movement/homing, temperatures and presets, a G-code library
and preview, printing with progress/fan/Z offset controls, extrusion/retraction,
motors, bed mesh, languages, firmware, statistics, and `M500` saving.
Postman/Bruno and Orca/Cura can upload files. “Upload & Print” remains unsupported.

We agreed to fix the issues first, then create a web dashboard with the same
components as the APK and video from the phone. We have implemented two rounds
of fixes; we have not started the web interface or video yet.
We will define remote access scope (LAN or Internet) and video requirements
when we reach that phase. We have not implemented camera support or the
`CAMERA` permission.

Write all documentation in English, using direct instructions and “we” for
shared decisions and work.

## Current architecture

| File | Responsibility |
| --- | --- |
| `lib/main.dart` | Providers, localization, navigation, and HTTP server lifecycle. |
| `lib/services/gcode_protocol.dart` | One USB subscription, a line buffer, and a FIFO; one command awaiting ACK. |
| `lib/services/usb_connection_service.dart` | USB 115200/8N1, handshake, queries, and validation of manual commands during printing. Replaces `usbConn_svc.dart`. |
| `lib/services/temp_svc.dart` | Temperatures/fan, one subscription, and at most one pending `M105` poll. |
| `lib/services/print_job_service.dart` | Shared job outside navigation routes, streaming reads, pause/cancel, and print states. |
| `lib/services/pause_parking.dart` | ACK-based command modes, homing/idle timeout, position/soft-limit parsing, and parking targets. |
| `lib/services/print_job_store.dart` | Versioned last-job record in SharedPreferences, restored as interrupted if previously active. |
| `lib/services/gcode_repository.dart` | Directory, permissions, metadata, thumbnails, import/upload, deletion, and write locking. |
| `lib/services/upload_api.dart` | Shelf handler with upload authentication and partial OctoPrint compatibility. |
| `lib/services/material_presets.dart` | Defaults and validated reading of saved presets. |
| `lib/pages/` | Home, library, job, preparation, extrusion, mesh, settings, and preset screens. |
| `lib/widgets/` | Responsive page layouts, control cards, movement controls, a keyboard-aware numeric form, stable thumbnails, and a selectable bed mesh. |

We will share these services between the APK and the future web interface.
Avoid adding another serial sender or a second source of print state.

## Contracts and behavior

- USB: first available device, 115200/8N1, and DTR/RTS. We wait for startup, initialize numbering with `M110 N0`, confirm `M105`, and initialize `G21`, `G90`, `M82`, and `M84 S120` before announcing a connection. The runtime motor timeout starts at 120 seconds; we do not write EEPROM. Debug builds use real hardware; there is no automatic simulation.
- Every command passes through the FIFO with a line number and checksum on Android. The transport owns numbering: external `M110` commands and files supplying their own numbers are rejected. Unnumbered mode remains available for tests. `ok` is recognized as a complete line; `busy`/temperature responses renew the inactivity timeout (10 s), with an absolute limit of 30 min per command.
- `Resend` for the pending line allows up to three identical retries; its transport ACK does not advance the print. Requests for acknowledged lines, unrecoverable errors, resets, write failures, or disconnections invalidate the session. Reconnect after these failures.
- During a job, manual temperature, fan, Z offset, and query controls remain available; movement, motors, and other operations are blocked. Z offset changes are also blocked during parking, pause, and return.
- Pause drains accepted moves, holds motors with `M84 S0`, verifies acknowledged homing, modes, `M114` position and enabled `M211` limits, then lifts Z up to 30 mm and parks toward Y maximum minus 5 mm. Less than 5 mm Z clearance or unavailable preflight data leaves a visible pause in place. Resume checks the reported position and limits, returns XY while elevated and then Z, verifies the return, and restores units, axes/extrusion modes and the previous runtime motor timeout before the next file line. A mismatched position fails the job; snapshots are never persisted. See [printing and mesh](docs/PRINTING_AND_MESH.md). Cancel waits for the current command, turns off the hotend/bed/fan, drains movements with `M400`, and attempts the same verified lift and rear parking. It reconciles interrupted pause/return stages without repeating a completed lift. If preflight is unavailable, cancellation remains in place and reports a warning; a position mismatch or command failure fails the job. No parking is attempted before any file command has been sent. Heating/probing in progress can delay cancellation.
- Completion requires the last ACK and the `M400` ACK. State and errors remain visible. The global “Active print” button opens the shared job from any screen; “Last print” in the library shows the previous or interrupted result.
- Successful cancellation returns to Home after the cooldown and movement barrier, and resets live progress, layer, elapsed and remaining time. The historical cancellation record remains persisted. A failed cancellation keeps its error visible and does not navigate home.
- The record is saved before the first send, every five seconds, and on pause/resume/cancel/completion. Writes are serialized; the record excludes thumbnails and does not allow resuming from an offset. Failure of the first save prevents the job from starting.
- Directory: `/storage/emulated/0/Download/gcode_files`. Classic storage permissions through Android 29; all-files access from Android 30. `MainActivity` exposes the SDK level through a MethodChannel to select the permission.
- Uploads: `POST /uploads` and `POST /api/files/local`, with the `X-Api-Key` header. The key is generated and persisted as `upload_api_key`; view/copy it from Home → API key. Cura no longer uses the dummy password `1234`.
- Existing names are not overwritten; paths, extensions other than `.gcode`, empty uploads, and writes during a job are rejected. Limits are 256 MiB per file and 512 MiB per request; files use temporary staging before publication and are cleaned up on failure.
- `GET /api/version` and `/api/settings` remain public for discovery without exposing the key. `OctoPrint 1.11.1` is a compatibility string, not the APK version.
- Shelf listens on port 8888 at the Wi-Fi IP, or `0.0.0.0` if unavailable. It closes when the root is unmounted. It does not yet provide a control dashboard or video.
- Orca/Cura metadata, the largest-area Base64 thumbnail, and progress from `M73` or layer comments are supported. Files are read as streams.
- Presets: `hotend_<material>` / `bed_<material>` keys, PLA/PETG/TPU/ABS materials; PLA bed temperature is 60 °C in both flows.
- Languages: en/es/ru/fr/de/it/pt, with 111 keys in each JSON. The persisted selection is no longer forced to English at startup.

## Environment and checks

Local Flutter SDK 3.29.3; declared Dart range `>=2.17.0 <4.0.0`. Android
minSdk 21, NDK 27.0.12077973, Java 11, AGP 8.7.0, Kotlin 1.8.22, Gradle 8.10.2.
`path` is a direct dependency; `flutter_test`, `flutter_lints`, and `fake_async`
are declared. We stopped ignoring `test/`, `analysis_options.yaml`, and
`pubspec.lock` so we can include them in repository changes.

```sh
flutter pub get --offline --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter build apk --debug --no-pub
python3 tool/check_translations.py
# In a checkout without android/key.properties:
python3 tool/validate_release_signing.py
git diff --check
# Refresh README screenshots with simulated data (no phone or printer):
flutter test --no-pub test/support/capture_screenshots.dart --reporter expanded
```

Flutter needs to write the SDK lockfile outside the repository; this sandbox
has required elevated permissions for that. We resolved new dependencies from
the local cache. Final results: zero analyzer issues, 47 passing tests, and a
debug APK built at `build/app/outputs/flutter-apk/app-debug.apk`.
We also validated rejection of a release without a key, a release with a
temporary certificate, and an unsigned release. Formatting and diff checks passed.

We prepared CI in `.github/workflows/ci.yml`: Flutter SDK and actions pinned
by commit; formatting, translations, analysis, tests, and build/signing
validation. We have not run it on GitHub because the changes are still local.

We chose AGPL v3: we declared `AGPL-3.0-only` and added the official text in
`LICENSE`. The later security audit found a locally signed release APK with a
different certificate from the debug APK and an existing `android/key.properties`.
We have not verified key custody or backups; preserve the existing key rather
than creating a replacement. Gradle no longer uses debug signing for releases:
it accepts `android/key.properties` or the
`CACOMIXTLE_STORE_FILE`, `CACOMIXTLE_STORE_PASSWORD`, `CACOMIXTLE_KEY_ALIAS`, and
`CACOMIXTLE_KEY_PASSWORD` variables. `CACOMIXTLE_ALLOW_UNSIGNED_RELEASE=true`
only enables unsigned validation. `tool/create_release_key.sh` creates a
dedicated key interactively; use it only when a new key is actually needed.
See [RELEASE.md](docs/RELEASE.md).

## Security review

We audited the current code, dependencies, and three local APKs on 2026-11-07.
The [security report](docs/SECURITY_AUDIT_2026-11-07.md) documents two High
current-code findings: cleartext API credentials/uploads and mutable jobs in
shared storage. We also reproduced two Medium issues and a historical High
upload traversal issue. The release contains Tika 3.1.0, covered by Critical
CVE-2025-66516; we have not established a reachable PDF/XFA exploit path.
SDK/native advisory matches are documented separately with their prerequisites.

We added six isolated reproductions in `tool/security_audit_poc.dart`. The
combined run passed 53 tests (47 existing plus six reproductions). These audit
tests assert vulnerable behavior; passing them does not demonstrate remediation.
We have not changed production code or dependencies as part of the audit.
Address the High findings and dependency updates before the web/video phase.

## Responsive UI

We updated all eight screens for constrained viewports, scrolling, and enlarged
text. Numeric forms switch to an inline layout when the keyboard leaves little
height; preset fields stack, and their Save button remains above the keyboard.
We added shared widgets under `lib/widgets/`, preserved existing movement
sequences, and fit the bed mesh to its canvas. The navigation bar hides while
the keyboard is visible. See [UI_RESPONSIVENESS.md](docs/UI_RESPONSIVENESS.md).

The full suite now passes 95 tests, including 48 new responsive UI checks.
We verified small landscape/portrait sizes, tablet width, 1.8× German text,
keyboard insets, form submission, and navigation. We also inspected temporary
rendered previews. Physical phone/IME validation remains pending. The security
report and its artifact hashes describe the snapshot before these UI changes;
its open findings still need remediation.
Static analysis is clean, translations remain aligned, and we rebuilt the
debug APK at `build/app/outputs/flutter-apk/app-debug.apk` successfully.

## Printing and mesh update

We fixed repeated thumbnail decoding during library, progress, and temperature
rebuilds. `GcodeThumbnail` retains its `MemoryImage` until the payload changes,
uses gapless playback, and isolates repainting.

We added `pausing` and `resuming` states. Parking/return runs in the print service
at ACK boundaries; Resume remains disabled until parking finishes. Cancel can
interrupt either transition after the pending ACK. Motion uses `G0` without E/F
to preserve the extruder coordinate and modal feedrate. We restore the idle
timeout on normal resume and connected-job cleanup, including cancellation and
failure. A reconnect explicitly sets the 120-second session default again.
`M18/M84 S…` changes the tracked timeout without invalidating homing. Commands
that disable motors invalidate homing. A recovered transition is interrupted,
with no physical return authorized.

The mesh now defaults to a selectable height map with a zero-centered blue/coral
legend and minimum/maximum/range summaries. We retain a 3D surface view. Mesh
indices are not millimeter coordinates; Y increases toward the top/rear. Dense
meshes scroll horizontally. Refresh errors preserve the previous valid mesh;
refresh and probing stay disabled throughout the whole operation.

The mesh point and summary information now appears beneath the mesh controls.
Point selection remains informational: editable points and printer motion have
not yet been implemented. The highlighted active-print button is global, and
movement controls grow with available width while preserving their commands.
The parking parser accepts the target firmware's colonless `M211` axis bounds;
parking still requires all existing safety checks. We have simulated the
user-supplied report from the installed firmware but have not tested physical motion.
The later navigation, cancellation, and movement-control changes passed all
123 tests with simulated transport, static analysis, formatting and translation
checks, and an Android debug build. Physical printer validation remains pending.

All 115 tests pass with simulated transport. We checked thumbnail frame/provider
stability, print page updates, parking/return modes and ordering, cancellation,
disconnection, travel bounds, interrupted history, and the responsive mesh UI.
All seven translations have 110 keys. Static analysis and diff checks are clean,
and we rebuilt the debug APK at `build/app/outputs/flutter-apk/app-debug.apk`.
We inspected rendered 4 × 4 mesh previews.
See [PRINTING_AND_MESH.md](docs/PRINTING_AND_MESH.md) for firmware references and
pending hardware checks. `M114` is a logical report, not a physical position
sensor: do not move the head or release motors during a pause.

## README screenshots

We added 15 current UI captures under `extras/screenshots/` and replaced the
older app images in the README. The earlier phone GIF stays available in a
clearly labeled expandable section; slicer and connection illustrations remain.
The README keeps its English, direct personal voice and describes the current
mesh, pause/resume, global print button, and responsive forms. Point calibration
is still labeled as planned work.

You can reproduce the images with
`flutter test --no-pub test/support/capture_screenshots.dart --reporter expanded`.
The opt-in fixture renders real page widgets with simulated state and synthetic
G-code thumbnails; it opens no USB ports or upload-server sockets. It reads the
version from `pubspec.yaml` and loads Roboto from installed Android SDK fonts.
The compact form simulates keyboard insets without drawing an Android keyboard.
See [SCREENSHOTS.md](docs/SCREENSHOTS.md) for setup and capture details. These
renders do not establish phone, IME, or physical printer behavior.

## Outstanding work

- We reviewed selected-point calibration in [MESH_POINT_CALIBRATION_REVIEW.md](docs/MESH_POINT_CALIBRATION_REVIEW.md). It remains a proposal: the LCD's point editor changes a mesh cell, while M851 changes the global probe offset. A future shared calibration session needs exclusive motion ownership, verified mesh coordinates, bounded 0.01 mm planned adjustments, readback, and explicit saving. The retained firmware report has Z minimum 0; negative targets and stationary babystepping require hardware-specific validation before enabling descent. We did not change production code or send printer commands during this review.
- We still need to validate with the phone and printer and test uploads from Orca/Cura; so far, our tests have used simulated transport. For parking, first check cold movement above an empty bed, normal/limited Z lifts, a pause longer than two minutes, return order, cancellation, and disconnection. Process death leaves the firmware runtime timeout unchanged; reconnect or restart before another job.
- Verify and back up your existing signing key and confirm its intended distribution identity. The audited local release already uses a different certificate from the old packaged APK.
- Remediate the open findings in the security report and repeat the relevant checks before adding remote controls.
- Let's run the workflow on GitHub when we push the changes.
- Movements do not resume after process death or power loss. The recovered record is informational; it does not prove the machine's physical position.
- Our next phase is to create the web dashboard, add video, and define remote access.
