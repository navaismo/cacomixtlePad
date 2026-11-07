#!/usr/bin/env bash
# Run in your own terminal. keytool asks for passwords without displaying them.
set -euo pipefail
umask 077

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
keystore_path="${1:-${project_dir}/.signing/release.p12}"

if ! command -v keytool >/dev/null 2>&1; then
  printf '%s\n' 'keytool is required. Use the JDK bundled with Android Studio or JDK 17.' >&2
  exit 1
fi
if [[ -e "$keystore_path" || -L "$keystore_path" ]]; then
  printf '%s\n' 'The destination already exists. Keep your existing key; it will not be overwritten.' >&2
  exit 1
fi
if [[ ! -t 0 ]]; then
  printf '%s\n' 'Run this script interactively in your own terminal to enter passwords.' >&2
  exit 1
fi

mkdir -p -- "$(dirname -- "$keystore_path")"
keytool -genkeypair -v -keystore "$keystore_path" -storetype PKCS12 \
  -alias cacomixtlepad -keyalg RSA -keysize 3072 -validity 10000

printf '\n%s\n' 'Keystore created. Back it up together with its password.'
printf 'Keystore: %s\n' "$keystore_path"
printf '%s\n' 'Copy android/key.properties.example to android/key.properties and fill it locally.'
printf '%s\n' 'Set storeFile to the path above. Do not commit the keystore or passwords.'
