# Android development and distribution

We use Flutter 3.29.3 and Java 17 to run Gradle, and compile Android code with
Java 11 compatibility. Our CI workflow pins the SDK and actions by commit.
It checks formatting, translations, analysis, tests, the debug APK, and release
builds with a temporary certificate and without signing. It keeps only the
debug APK as a test artifact; it does not publish releases or need private keys.

## Local checks

```sh
flutter pub get --enforce-lockfile
python3 tool/check_translations.py
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter build apk --debug --no-pub
```

Your test APK is at `build/app/outputs/flutter-apk/app-debug.apk`.
Debug builds control the real printer; they do not enable automatic simulation.

## Create a distribution key

To sign your release, you need a keystore, its alias, and the store and key
passwords. Keep the same key for future versions.
The [Android signing documentation](https://developer.android.com/studio/publish/app-signing)
describes app identity and update requirements.

We no longer sign releases implicitly with the debug key. Our configuration
follows the `key.properties` setup in the
[Flutter release guide](https://docs.flutter.dev/deployment/android#sign-the-app).

In your own terminal, run:

```sh
bash tool/create_release_key.sh
cp android/key.properties.example android/key.properties
```

The script calls the JDK's `keytool` and asks for certificate details and a
password interactively. It creates `.signing/release.p12` with the alias
`cacomixtlepad`; it does not overwrite an existing key. You can pass another
keystore path as the first argument.

Fill in `android/key.properties` locally with your password in `storePassword`
and `keyPassword`. The PKCS12 format created by the script uses the same
password for both. The `storeFile` path is resolved from `android/`, or it can
be absolute. Back up your keystore and its password. Git ignores the keystore
and the file containing passwords.

Then run:

```sh
flutter build apk --release --no-pub
```

Your signed APK is at `build/app/outputs/flutter-apk/app-release.apk`.
If configuration is missing, the build fails with the names of the missing
fields; it does not print passwords or fall back to debug signing.

You can also provide all four fields through environment variables:

| Variable | Field in `key.properties` |
| --- | --- |
| `CACOMIXTLE_STORE_FILE` | `storeFile` |
| `CACOMIXTLE_STORE_PASSWORD` | `storePassword` |
| `CACOMIXTLE_KEY_ALIAS` | `keyAlias` |
| `CACOMIXTLE_KEY_PASSWORD` | `keyPassword` |

Each variable overrides its field in the file. Set them in your local
environment or a secret store; do not pass passwords as build arguments.

An APK signed with a different key from an existing installation cannot
replace it directly as an update. Previous APKs from this project used the
debug key. Before migrating an installation, keep any data you need; creating
a new key does not convert the previous signature.

## Build an unsigned release for validation

CI has no distribution key. To validate Dart AOT, Gradle, and R8, explicitly use:

```sh
CACOMIXTLE_ALLOW_UNSIGNED_RELEASE=true flutter build apk --release --no-pub
```

Use that artifact to check the build, not for installation or distribution.
The option forces unsigned output even when local signing configuration is
present. Without that variable, a release build requires configured signing.

The `python3 tool/validate_release_signing.py` script checks these cases and
verifies that the APK certificate matches the temporary keystore. Run it in
a checkout without `android/key.properties`. It restores previous artifacts
and removes the temporary validation keys and APKs.

## License

We chose AGPL v3 for this project. We declare `AGPL-3.0-only` in the README and
include the unmodified official text in [LICENSE](../LICENSE), obtained from
[GNU](https://www.gnu.org/licenses/agpl-3.0.txt).
