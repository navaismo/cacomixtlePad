# Security audit — 2026-11-07

We reviewed our current local code, resolved dependencies, and three APKs before
continuing feature work. We found **two High issues and two Medium issues in
our current code**, plus a High issue reproduced in our historical baseline.
We also confirmed that our release APK includes a dependency version covered
by a **Critical advisory**. We have not established an exploitable Critical
path in this app.

We have not applied remediation in this audit. The reproductions intentionally
assert the vulnerable behavior; passing them confirms the findings, not that
the app is secure.

## Scope and evidence

We reviewed the uncommitted worktree based on `9f7a9e1`, including the HTTP upload
API, file storage, G-code streaming, serial protocol, Android permissions,
signing configuration, Flutter engine, and native plugin dependencies.
[Snapshot hashes](security/evidence/reviewed_snapshot.json) identify the main
files we reviewed. We used static analysis, APK manifest/signature/DEX
inspection, online advisory queries, a loopback HTTP request, and simulated
printer tests. We did not connect to a phone, send commands to a physical
printer, capture a real network session, or perform a full native exploit.

Our [six isolated reproductions](../tool/security_audit_poc.dart) use temporary
files, a dummy API key, and a fake printer. The full run passed **53 tests**:
47 existing tests plus six audit reproductions. See the
[test output](security/evidence/test_results.txt).

We assign application severities based on the prerequisites and impact below.
Vendor advisory severities describe the affected component; they do not prove
that its vulnerable entry point is reachable in our app.

## Prioritized findings

| ID | Severity | Finding | Evidence and applicability |
| --- | --- | --- | --- |
| APP-01 | High | HTTP exposes the persistent API key and permits modification of uploads in transit | Current code and loopback transport reproduction |
| APP-02 | High | Shared-storage G-code can change after review and during printing | Current service reproduced with a fake printer; Android filesystem access prerequisites apply |
| BASE-01 | High | Historical upload handler permits unauthenticated writes outside the G-code directory | Reproduced from `9f7a9e1`; fixed in the worktree; old packaged APK needs on-device verification |
| DEP-01 | Critical upstream; app exploit unconfirmed | `tika-core:3.1.0` matches CVE-2025-66516 | Dependency and relevant classes confirmed in release APK; PDF/XFA entry point not found |
| APP-03 | Medium | One invalid UTF-8 upload prevents loading the whole library | Reproduced against the current authenticated API |
| APP-04 | Medium | Uploads lack aggregate storage quotas, concurrency limits, and an absolute deadline | Aggregate quota gap reproduced; exhaustion and long-lived upload effects assessed from code |

### APP-01 — Persistent credential and G-code travel over HTTP

**Location:** [lib/main.dart](../lib/main.dart), lines 99–134;
[upload_api.dart](../lib/services/upload_api.dart), lines 33–35.
**Weaknesses:** CWE-319, CWE-345.

We start Shelf without a TLS `SecurityContext` and advertise `http://` URLs.
Authentication consists of a persistent bearer key in `X-Api-Key`. We generate
that key securely, but the transport exposes it together with the G-code.
There is no key rotation control or request freshness mechanism.

An attacker who can observe or control the network path during a legitimate
upload can recover the key and replay authenticated uploads. An active
intermediary can also alter the original upload's contents before storage.
Sharing an SSID alone does not guarantee that traffic can be intercepted;
the prerequisite is access to the traffic path, such as a compromised access
point or a successful local interception attack.

**Impact:** unauthorized file creation and loss of G-code integrity. Our current
API does not expose a remote print/start endpoint, and its collision checks
prevent overwriting an existing name through a normal authenticated upload.
We do not claim immediate remote control of the printer. Modified G-code can
affect the printer when you later start that job.

**Reproduction:** the `HTTP exposes the reusable API credential to the transport`
test sends a multipart request over a raw TCP socket, without TLS. The same
upload handler accepts the visible dummy key and returns `200 OK`. This proves
the cleartext protocol; we did not intercept a real credential.

**Remediation:** protect uploads with authenticated TLS, or place the service
behind a trusted encrypted tunnel with access controls. Define a slicer pairing
and certificate trust flow. Add key rotation/revocation. If plain HTTP remains
available for compatibility, make that a deliberate restricted deployment mode
and do not expose it directly to the Internet. Setting Android client cleartext
flags alone does not encrypt our inbound Dart HTTP server.

**Retest:** a raw HTTP request must not transmit a usable credential or job;
verify certificate trust, key revocation, and failure on in-transit changes.
This risk is consistent with
[Android's cleartext communication guidance](https://developer.android.com/privacy-and-security/risks/cleartext-communications).

### APP-02 — A print is streamed from a mutable shared file

**Location:** [gcode_repository.dart](../lib/services/gcode_repository.dart),
lines 55–61, 81–94, and 155–176;
[print_job_service.dart](../lib/services/print_job_service.dart), lines 161–229.
**Weaknesses:** CWE-367, CWE-922.

We store executable printer jobs in
`/storage/emulated/0/Download/gcode_files`. The preview records a filename and
metadata, not an immutable version of the content. Starting a job reopens that
path and streams it. `repository.locked` only blocks our own repository methods;
it does not prevent another process from writing to the underlying file.

**Prerequisite:** another app or local actor must have write access to that
shared directory. On supported older Android devices, legacy external-storage
permissions can provide that access. On newer Android versions, an app with
granted all-files access or another applicable grant can write there. An
ordinary sandboxed app without such access does not automatically qualify.

**Impact:** an attacker with that access can replace reviewed G-code or alter
unread portions of an active job. We then send those changed commands through
the legitimate serial connection without further approval. Physical effects
depend on the commands and the printer's firmware protections; we did not test
or claim a firmware safety bypass.

**Reproduction:** two tests replace `M117 ORIGINAL` with `M117 MODIFIED`:

1. After library metadata is read but before the print starts.
2. After the first command is sent, while `repository.locked == true`, in a
   file region beyond the buffered prefix.

Both tests observe the modified command in the fake printer's outgoing stream.
No commands reach hardware.

**Remediation:** import/upload into app-private internal storage and create an
immutable private snapshot for each selected job. Associate preview approval
with that snapshot or a digest of its complete content. Print that exact
snapshot. A single hash check followed by streaming the mutable shared source
still leaves a race. Use Android's document picker for imports and remove broad
storage permissions when they are no longer needed.

**Retest:** modifying the external original before or during printing must either
leave the approved private snapshot unchanged or prevent the job from starting.
See [Android's external-storage security guidance](https://developer.android.com/privacy-and-security/risks/sensitive-data-external-storage).

### BASE-01 — Unauthenticated path traversal in the historical upload handler

**Location:** `git show 9f7a9e1:lib/main.dart`, upload handler around lines 119–140.
**Weaknesses:** CWE-306, CWE-22, CWE-73.

Our baseline accepts multipart uploads without a credential. It joins the
untrusted filename to the shared G-code directory and opens the result for
writing, without checking traversal, extension, collisions, size, or print state.

**Reproduction:** we copied that upload branch into an isolated test, replacing
only the Android destination directory with a temporary directory. A request
without `X-Api-Key`, carrying `filename="../outside.gcode"`, returns `200` and
creates a file outside the intended library. The write remains bounded by the
app's filesystem permissions; this is not proof of writing private data owned
by another Android app or of Android code execution.

**Current status:** our worktree rejects unauthenticated requests and invalid
basenames; existing tests cover those restrictions. The older
`package/cacomixtlePad-v1.1.0.apk` is a separate artifact. Its native strings lack
the API-key identifiers present in our new release and are consistent with the
old code, but we did not execute its upload endpoint. Do not equate the source
reproduction with a completed on-device exploit of that APK.

**Remediation:** replace obsolete distributed artifacts with an audited build,
identify installations still running the old version, and verify the legacy
APK's endpoint in an isolated device lab. Increase `versionCode` for the next
release; all inspected APKs currently declare code `1` and name `1.1.0`.
Account for the signing identity change described below.

### DEP-01 — Critical advisory in the Android file-picker dependency

**Dependency chain:** `file_picker 10.1.9` →
`org.apache.tika:tika-core:3.1.0`.
**Advisory:** [CVE-2025-66516 / GHSA-f58c-gq56-vjjf](https://github.com/advisories/GHSA-f58c-gq56-vjjf),
Critical, vendor CVSS v4 score 10.0; affected through 3.2.1, fixed in 3.2.2.

We confirmed the version in the app's release runtime dependency model and
confirmed `org.apache.tika.Tika` and `org.apache.tika.utils.XMLReaderUtils` in
the actual release DEX. The plugin also keeps Tika classes through its ProGuard
rules. This is a real component match, not merely an old cached JAR.

The advisory concerns external-entity processing of XFA inside PDF parsing.
Our inspected plugin calls Tika's MIME detection APIs. Our Dart app uses
`pickFiles`; we did not find a call into PDF/XFA parsing, a PDF parser module
in the runtime model, or the expected PDF parser classes in the DEX listing.
We therefore **have not confirmed XXE, local file disclosure, SSRF, or remote
code execution in this app**. A Critical scanner match must not be presented
as an exploitable Critical application finding without that path.

**Remediation:** upgrade or replace the picker dependency so the resolved
`tika-core` is at least 3.2.2, or remove Tika if we do not need it. Verify Android
compatibility and dependency resolution rather than changing only the Dart
constraint. Check the rebuilt APK and rerun the advisory scan.

**Retest:** the release runtime model must contain a patched Tika version or no
Tika, and the APK must reflect that result. If we later add document parsing,
include explicit XXE tests before exposing it.

### APP-03 — A malformed file poisons the library listing

**Location:** [upload_api.dart](../lib/services/upload_api.dart), lines 55–59;
[gcode_repository.dart](../lib/services/gcode_repository.dart), lines 155–176;
[print_page.dart](../lib/pages/print_page.dart), lines 38–56 and 151–156.
**Weakness:** CWE-20 / availability through unhandled per-file parsing errors.

An authenticated upload is validated by its filename and byte count, not by
text encoding. `list()` parses every file with the strict UTF-8 decoder, and
one failure aborts the complete listing. The screen displays an error instead
of the library, including its normal per-file deletion controls.

**Reproduction:** upload a valid job and `poison.gcode` containing the three bytes
`FF FE 0A`. Both uploads return `200`; `repository.list()` throws
`FormatException`. Deleting the malformed file restores listing. An actor with
shared-directory write access can trigger the same behavior without the API.

**Remediation:** validate accepted text encoding at ingestion and isolate
per-file metadata errors. Quarantine or show invalid files with a removal
control while keeping valid jobs accessible. Apply the same policy to imports.

**Retest:** invalid UTF-8 must be rejected or isolated; existing valid jobs must
remain visible and selectable.

### APP-04 — Per-request limits do not bound total resource use

**Location:** [upload_api.dart](../lib/services/upload_api.dart), lines 11–13,
37–56; [gcode_repository.dart](../lib/services/gcode_repository.dart),
lines 49–63 and 97–140.
**Weakness:** CWE-400 / CWE-770.

We enforce 256 MiB per file and 512 MiB per request, but have no total library
quota, free-space reserve, or upload concurrency limit. The 30-second stream
timeout measures inactivity, not total upload duration. A slow authenticated
sender can keep a pending upload alive by delivering data within each interval.
A pending file also prevents starting a print through `mutationsInProgress`.

**Reproduction:** with a deliberately small per-file limit, ten separately
accepted API uploads exceed that limit in aggregate. This confirms that a
per-file limit is not a total quota. We did not fill the disk or launch a
connection flood; long-lived-upload and concurrency impacts are code-based.

**Impact:** a holder of the upload credential can consume storage repeatedly,
reserve upload resources, or delay job startup. An active print blocks newly
received uploads, which reduces exposure; it does not provide aggregate
resource accounting.

**Remediation:** reserve space before accepting uploads, enforce a total quota
and a minimum free-space reserve, limit concurrent uploads, add an absolute
request deadline, and provide cancellation. Enforce limits on multipart
headers as well as file bodies. Bound metadata line lengths and decoded image
sizes so a small accepted file cannot demand disproportionate memory later.

**Retest:** repeated legal-sized uploads, slow streams, parallel uploads, and
oversized multipart headers must fail predictably without exhausting storage
or preventing normal recovery.

## Dependency triage beyond the main findings

We queried OSV on 2026-11-07 with the versions in `pubspec.lock` and the local
Gradle models. Our [Pub scan](security/evidence/osv_pub.json) returned no matches
for **89 hosted Pub packages**. Our broader
[Maven scan](security/evidence/osv_maven_all_models.json) checked 109 unique
coordinates across local models. The final app's package section contains
**83 external Maven coordinates**; its
[filtered scan](security/evidence/osv_maven_app_runtime.json) contains the Tika
match. These database results do not establish that unlisted packages are safe.

| Component | Result | Applicability and action |
| --- | --- | --- |
| Apache Tika 3.1.0 | Critical CVE-2025-66516 | Confirmed in app runtime and release DEX; see DEP-01 for reachability limits and remediation. |
| Okio 2.1.0 | Moderate CVE-2023-3635 in a plugin-local model | Excluded from app findings: the final app resolves `okio-jvm:3.4.0`, the patched version. Do not report the older plugin model as the shipped version. |
| Dart 3.7.2 / Flutter 3.29.3 | High GHSA-frr6-h895-5pxp | Matches the SDK range, but requires outbound `dart:io` TLS. We found no such app path; our upload endpoint is inbound plain HTTP. Keep this as an SDK update requirement, not a demonstrated exploit. |
| Native libpng `1.6.43.git` | High advisories including CVE-2026-33636 and CVE-2026-33416 | Version banner confirmed in both inspected release engine binaries. We inspected pinned native sources; the relevant decoder call patterns are not established as reachable. Update the engine and verify patches; do not claim native RCE from the banner. |
| Dart Pub extraction | Low CVE-2026-27704 | Affects the old build toolchain with malicious package archives; our locked hosted dependencies use pub.dev, covered by the advisory's mitigation. This is not an APK runtime finding. |

For Okio, the [upstream advisory](https://github.com/advisories/GHSA-w33c-445m-f8w7)
identifies 3.4.0 as patched. The
[Dart TLS advisory](https://github.com/dart-lang/sdk/security/advisories/GHSA-frr6-h895-5pxp)
sets fixed stable floors of Dart 3.13.7 and Flutter 3.47.8. Rebuild with a
maintained SDK containing those fixes; this floor addresses that advisory,
not every future engine vulnerability. See also the
[Pub extraction advisory](https://github.com/dart-lang/sdk/security/advisories/GHSA-q739-79rh-vmvp).

For libpng, Flutter's pinned build enables ARM Neon, but the pinned Skia decoder
uses its own palette representation rather than calling
`png_set_palette_to_rgb` in the inspected palette path. We also did not find
the simplified read or repeated palette/transparency setter pattern required
by the reviewed advisories. These are reasons to investigate reachability,
not to declare a confirmed heap exploit. References:
[Flutter 3.29.3 dependency pins](https://github.com/flutter/flutter/blob/3.29.3/DEPS),
[pinned libpng build](https://flutter.googlesource.com/third_party/libpng/+/de36b892e921c684ef718fec24739ae9bb49c977/BUILD.gn),
[pinned Skia decoder](https://skia.googlesource.com/skia/+/e7b8d078851fd505475fe74359e31a421e6968ea/src/codec/SkPngCodec.cpp),
[Neon advisory](https://github.com/pnggroup/libpng/security/advisories/GHSA-wjr5-c57x-95m2),
[setter aliasing advisory](https://github.com/pnggroup/libpng/security/advisories/GHSA-m4pc-p4q3-4c7j).

## APK inspection

Our [APK inventory](security/evidence/apk_inventory.json) records SHA-256 hashes,
signature verification, permissions, native libraries, and embedded AndroidX
versions. All three APKs use application ID `com.shaka.cacomixtlePad`, minSdk 21,
targetSdk 35, version name `1.1.0`, and versionCode `1`.

| Artifact | APK SHA-256 | Signing and debug status |
| --- | --- | --- |
| `package/cacomixtlePad-v1.1.0.apk` | `6515c6cd86c442a164146badd95fbbe94f0c06132671b222ac87601dcd7e5855` | Android Debug certificate; manifest is not debuggable |
| `build/app/outputs/flutter-apk/app-debug.apk` | `38987409262c7036a46a8d682e6fbe3bfc2e9def9c2ec356eb9f118606f44165` | Android Debug certificate; debuggable as expected for development |
| `build/app/outputs/flutter-apk/app-release.apk` | `9565e80cb45ac1fdb635f9df88197d3d251727bc20377bbbea58776853853f44` | Different RSA-3072 certificate; manifest is not debuggable |

The current local release is already signed with a different certificate from
the old packaged APK. Its certificate SHA-256 is
`b51beb17d0b128b8824ec22af145c3b04bc314cd185a13c6c8d3843c52690198`;
the old APK and local debug build use
`893e036ab52c142a48707a925469a332cec37cd175a77dd7ffdb8319b76c35fc`.
This supersedes the earlier memory's assumption that no distribution signature
existed. We did not read passwords or verify key backup/custody. A certificate
named Android Debug is not proof that its private key is publicly known.

The APKs verify with v1 and v2 signatures. We did not classify absence of v3/v4
or SourceStamp as a standalone High vulnerability. The exported launcher and
permission-protected AndroidX profile receiver are not evidence of an
unauthorized printer command endpoint. The startup provider is not exported.

We noted broad external-storage access and default backup behavior for future
hardening. The manifest does not explicitly configure backup exclusions, and
the API key is persisted in SharedPreferences. Review backup/transfer handling
for credentials and add a rotation flow; we have not demonstrated unauthorized
backup extraction. Do not distribute the development APK as the production fix.

## Remediation order and acceptance

1. Fix APP-01 and APP-02 before adding remote monitoring or printer controls.
   Encryption and immutable job storage protect different trust boundaries;
   both need verification.
2. Remove or update the affected Tika dependency, then rebuild and inspect the
   release APK. Update the Flutter/Dart engine and scan native dependencies,
   retaining the reachability distinctions documented above.
3. Fix malformed-file isolation and resource limits. Add regression tests that
   assert the intended secure behavior; our audit reproductions currently
   assert the vulnerable behavior and must not become a permanent success gate.
4. Replace obsolete distributable APKs with a versioned, audited release and
   define migration for the signing change. Preserve any required data first.
5. Validate on isolated Android devices with the supported storage models and
   a simulated printer before physical printer testing. Verify old-APK HTTP
   behavior, actual network exposure, file tampering resistance, and recovery.

To repeat our local evidence collection checks:

```sh
flutter test tool/security_audit_poc.dart --no-pub --reporter expanded
flutter test test tool/security_audit_poc.dart --no-pub --reporter expanded
flutter analyze --no-pub tool/security_audit_poc.dart
# Use your installed Android build-tools path:
apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
aapt dump badging build/app/outputs/flutter-apk/app-release.apk
apkanalyzer dex packages --defined-only build/app/outputs/flutter-apk/app-release.apk
```

We have not proven an end-to-end Critical exploit or native code execution.
Our actionable current findings are supported by code and bounded local
reproductions; device-specific exploitability remains subject to the stated
prerequisites and follow-up checks.
