# Repository context

Read [MEMORY.md](MEMORY.md) when starting a task. It covers the architecture,
commands, and current status. The [initial analysis](docs/REPO_ANALYSIS.md)
is historical; refer to the reports for the [first round](docs/FIXES_2026-11-07.md)
and [second round](docs/FIXES_2026-11-07_2.md) of fixes.

## Working on this project

- Android is our implemented platform; the app controls a Marlin printer over USB OTG.
- Keep the Dart package name `CacomixtlePad` and preserve its capitalization in imports.
- Route every command through `UsbConnectionService.execute` and `GcodeProtocol`. Do not add direct port writes or USB listeners to screens.
- Keep the print job in `PrintJobService`, outside navigation routes. Share these services between the APK and the future web interface.
- Debug builds also control real hardware. Tests explicitly simulate the transport; distinguish their results from physical validation.
- Keep translatable text in `assets/lang/` and maintain the keys across all seven languages.
- Preserve upload routes and slicer compatibility, including `X-Api-Key`, unless the task calls for changing them.
- Check `git status --short` before editing and keep changes within the task's scope.
- Run the relevant analysis and tests; check the build after Android changes when the environment allows it.
- Update the memory when architecture, commands, or outstanding work change. Do not record credentials or describe proposals as implemented changes.
- Preserve line numbering, checksums, and `Resend` validation; do not resend movements that have already been acknowledged.
- Use the persisted record to identify interrupted jobs; it does not authorize automatically resuming movements.
- Sign release builds with a dedicated key. Create keys interactively and keep them out of Git. Use temporary certificates only for validation.
- Our license is `AGPL-3.0-only`.
- Write all documentation in English. Keep a direct, personal voice: address instructions to “you” and describe shared decisions or work as “we.”
- For UI changes, use available layout constraints and text scaling, keep controls scrollable and touchable, and check small viewports with keyboard insets.
