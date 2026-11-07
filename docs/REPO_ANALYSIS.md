# Initial repository analysis

> We keep this analysis as a historical reference for the baseline below.
> We documented the first round of fixes in
> [FIXES_2026-11-07.md](FIXES_2026-11-07.md). Read
> [MEMORY.md](../MEMORY.md) for the current architecture and outstanding work.

Date: 2026-11-07. Baseline: `9f7a9e1`. Scope: application Dart code
(3,752 lines, excluding generated keys), Android configuration, dependencies,
translations, documentation, and test status.

The app has a small structure that is easy to navigate: Flutter screens,
two shared services, and a Shelf server integrated at the root. The main
weakness is that several consumers write to and read from the same port
without a central command queue or a shared line parser.
We found these issues by inspecting the code. We did not reproduce them
on a physical printer during this initial review.

## High-priority findings

1. **An `ok` can release the wrong command.**
   `lib/pages/print_job.dart:121` advances on any fragment containing `ok`;
   `lib/services/usbConn_svc.dart:121` applies the same criterion to
   `awaitGcode`. Meanwhile, `lib/services/temp_svc.dart:37` writes `M105`,
   and manual controls also write directly. A query or control ACK can be
   consumed as confirmation of a print line. Incomplete fragments are not
   retained, and multiple ACKs in the same fragment are not processed
   individually. This can break flow control or leave it waiting indefinitely.
   Printing also lacks an ACK timeout, `Resend` recovery, and an explicit
   transition to failure on firmware errors.

2. **Temperature polling accumulates listeners without releasing them.**
   `lib/services/temp_svc.dart:38` opens a subscription every two seconds;
   `stop()` only cancels the timer. Each response ends up passing through an
   increasing number of callbacks. `getFWInfo`, `getStats`, and `getBLGrid`
   also fail to cancel their subscriptions when their timeouts expire.
   The local USB plugin stream is broadcast: the problem is accumulation
   and concurrent processing, not a restriction against listening twice.

3. **Leaving the screen loses the active job sender.**
   `lib/pages/print_job.dart:48` cancels `_serialSub` in `dispose`, but does
   not keep the print in a service or prevent leaving with an active job.
   The printer can finish the commands already in its buffer and run out of
   new lines. That `dispose` also does not cancel the elapsed-time timer,
   which can try to call `setState` after the screen is unmounted.

4. **The job is marked complete when the last line is sent.**
   `lib/pages/print_job.dart:216` checks for completion using the index after
   sending, cancels the subscription, and announces success without waiting
   for the last ACK. There is also no explicit barrier for pending movements
   before announcing physical print completion.

5. **HTTP uploads allow names and writes without their own restrictions.**
   `lib/main.dart:126` joins the directory with the received multipart
   `filename` without validating basename, extension, containment, size, or
   collisions. A name containing `../` can escape the intended directory
   within the process's permissions; a collision overwrites the destination.
   The endpoint is available without authentication to anyone who can reach
   the server and does not check print state. This also contradicts the
   README's stated restriction on uploads during printing.

## Medium-priority findings

- **You cannot import the first file from an empty library.**
  `lib/pages/print_page.dart:215` returns only a spinner when the list is
  empty, before building the import button. The same state represents
  loading, no files, and read failure. HTTP uploads also do not notify this
  screen directly to reload its list.
- **Saved presets are not preloaded in the editor.**
  `lib/pages/material_values.dart` initializes lists with constant values
  and only uses preferences when saving. Reopening and saving can replace
  previous customizations. The PLA bed also uses 60 °C in the editor and
  61 °C as the fallback in `home_page.dart`.
- **Cancellation and extrusion rely on assumptions about physical state.**
  `lib/pages/print_job.dart:296` sends `G90` and an absolute move to Z15:
  if the print is above that height, the move lowers the head while moving
  along XY. `lib/pages/extrude_retract.dart:61` uses `G1 E…` without setting
  the extrusion mode; its meaning depends on the firmware's previous mode.
  Let's review both flows against the machine's actual state before changing them.
- **Queries can interpret partial responses.**
  Firmware and statistics look for text in a single USB block. The mesh
  accumulates data, but requires the specific CATMULL ROM subdivision
  terminator and also lets the numeric header through as if it were a row.
  Later rows can overwrite those header values in the usual case;
  dimensions and completeness are not validated.
- **Resource cleanup is incomplete.**
  The root does not close its HTTP server in `dispose`; the close call in
  `PrintPage` refers to another field that is never initialized. The USB
  connection listener is not saved for cancellation, reconnection does not
  close the previous port first, and the root starts temperature polling
  from `build` without explicitly stopping it on disconnect. Several screens
  have asynchronous UI callbacks without `mounted` checks.
- **Permissions and file failures lack a consistent recovery path.**
  After storage access is denied, initialization continues trying to start
  the server or read files. Reading all G-code files fully in parallel and
  using `readAsLines` for printing can consume a lot of memory; invalid
  Base64 thumbnails are decoded without error handling.
- **Release builds are signed with the debug key.**
  This is explicit in `android/app/build.gradle.kts`. We did not check
  publication or installation of a new build during this review.

## Validation performed

`flutter analyze --no-pub` exited with code 1 and **26 issues**:

| Type | Count | Cause |
| --- | ---: | --- |
| Error | 18 | Obsolete local counter test: missing `flutter_test`, import with different capitalization, nonexistent `MyApp`, and unresolved dependent symbols. |
| Warning | 3 | Missing `flutter_lints` include and two dead-code branches in extrusion/retraction. |
| Information | 5 | Four uses of `withOpacity` deprecated in the local SDK and one unnecessary import. |

The test errors do not demonstrate a production code build failure. This
analysis does not prove that an Android build passes either. Git ignores
the test file and analyzer configuration: a clean checkout can produce a
different result. There are no versioned protocol tests or CI workflow;
the local template test remains.

We reviewed all seven translation JSON files: en/de have 73 keys and the
others have 72. `App_settings_saved` is missing in es/fr/it/pt/ru. The literal
key `Close`, used in settings, is absent from every file. This check compares
literal keys; it does not guarantee coverage of dynamically constructed text.

The app imports `path`, but it is not declared directly in `pubspec.yaml`;
it is currently resolved through transitive dependencies.
The README declares AGPL, but there is no versioned license file specifying
the version and applicable text.

During this initial review, we did not run `flutter test`, APK builds, or
hardware tests. We also did not consult external services or modify the
application code.

## Suggested order for subsequent work

1. Let's unify USB reception with line buffering, a command queue, correlated
   ACKs, errors, timeouts, and subscription cleanup.
2. Let's extract the print job into a service with explicit states and verify
   leaving the screen, disconnection, pause, cancellation, and actual completion.
3. Let's validate and limit HTTP uploads, collisions, and changes to files in use.
4. Let's fix the empty library, preset loading, and permission/thumbnail errors.
5. Let's add protocol tests for fragmentation, multiple ACKs, interleaved `M105`,
   errors, and end of file; replace the template test and fix analysis
   configuration and version control exclusions.

At this point, we had only proposed these changes; we had not implemented
them or agreed on them as final decisions.
