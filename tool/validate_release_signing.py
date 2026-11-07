#!/usr/bin/env python3
"""Exercise release signing with an ephemeral certificate, never a real key."""
import hashlib
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    if (ROOT / "android/key.properties").exists():
        raise SystemExit("Run in a checkout without android/key.properties; real signing keys are never used by this check.")
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not sdk:
        local = ROOT / "android/local.properties"
        for line in local.read_text().splitlines() if local.exists() else []:
            if line.startswith("sdk.dir="):
                sdk = line.split("=", 1)[1]
    if not sdk:
        raise SystemExit("Set ANDROID_HOME to the Android SDK path.")
    candidates = list((Path(sdk) / "build-tools").glob("*/apksigner"))
    if not candidates:
        raise SystemExit("Install Android SDK build-tools (apksigner is required).")
    apksigner = max(candidates, key=lambda p: tuple(int(n) for n in re.findall(r"\d+", p.parent.name)))
    for executable in ("flutter", "keytool"):
        if not shutil.which(executable):
            raise SystemExit(f"{executable} is required.")
    environment = {k: v for k, v in os.environ.items() if not k.startswith("CACOMIXTLE_")}
    password = secrets.token_urlsafe(32)

    def run(command, env=environment):
        return subprocess.run(command, cwd=ROOT, env=env, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def require(result, message, succeeds=True):
        if (result.returncode == 0) != succeeds:
            safe = result.stdout.replace(password, "[validation password]")
            raise RuntimeError(f"{message}\n" + "\n".join(safe.splitlines()[-60:]))

    artifacts = [ROOT / "build/app/outputs" / name for name in (
        "flutter-apk/app-release.apk", "flutter-apk/app-release.apk.sha1",
        "apk/release/app-release.apk", "apk/release/app-release-unsigned.apk",
        "apk/release/output-metadata.json")]
    with tempfile.TemporaryDirectory(prefix="cacomixtle-signing-check-") as temporary:
        temporary = Path(temporary)
        backups = {}
        for i, artifact in enumerate(artifacts):
            if artifact.exists():
                backup = temporary / f"artifact-{i}"
                shutil.copy2(artifact, backup)
                backups[artifact] = backup
        try:
            print("[1/3] Checking that release without signing configuration fails", flush=True)
            result = run(["flutter", "build", "apk", "--release", "--no-pub"])
            require(result, "Release unexpectedly accepted missing signing configuration", succeeds=False)
            if "Release signing is not configured" not in result.stdout:
                raise RuntimeError("Build failed for a different reason:\n" + result.stdout[-6000:])

            print("[2/3] Building and verifying a release with a temporary certificate", flush=True)
            fixture = environment | {
                "CACOMIXTLE_STORE_FILE": str(temporary / "validation.p12"),
                "CACOMIXTLE_STORE_PASSWORD": password,
                "CACOMIXTLE_KEY_ALIAS": "validation",
                "CACOMIXTLE_KEY_PASSWORD": password,
            }
            result = run(["keytool", "-genkeypair", "-keystore", fixture["CACOMIXTLE_STORE_FILE"],
                          "-storetype", "PKCS12", "-alias", "validation", "-keyalg", "RSA",
                          "-keysize", "2048", "-validity", "1", "-dname", "CN=Build validation only",
                          "-storepass:env", "CACOMIXTLE_STORE_PASSWORD"], fixture)
            require(result, "Unable to generate temporary validation certificate")
            require(run(["flutter", "build", "apk", "--release", "--no-pub"], fixture), "Signed build failed")
            certificate = temporary / "certificate.der"
            require(run(["keytool", "-exportcert", "-keystore", fixture["CACOMIXTLE_STORE_FILE"],
                         "-alias", "validation", "-storepass:env", "CACOMIXTLE_STORE_PASSWORD",
                         "-file", str(certificate)], fixture), "Unable to export validation certificate")
            apk = ROOT / "build/app/outputs/flutter-apk/app-release.apk"
            verified = run([str(apksigner), "verify", "--print-certs", str(apk)])
            require(verified, "APK signature validation failed")
            expected = hashlib.sha256(certificate.read_bytes()).hexdigest()
            actual = re.search(r"Signer #1 certificate SHA-256 digest: ([a-fA-F0-9]+)", verified.stdout)
            if not actual or actual.group(1).lower() != expected:
                raise RuntimeError("APK was not signed by the configured validation certificate")

            print("[3/3] Checking explicit unsigned release compilation", flush=True)
            unsigned = fixture | {"CACOMIXTLE_ALLOW_UNSIGNED_RELEASE": "true"}
            require(run(["flutter", "build", "apk", "--release", "--no-pub"], unsigned), "Unsigned release build failed")
            result = run([str(apksigner), "verify", "--print-certs", str(apk)])
            require(result, "Unsigned validation build unexpectedly has a signature", succeeds=False)
            if "DOES NOT VERIFY" not in result.stdout:
                raise RuntimeError("Unsigned artifact verification failed for an unexpected reason")
            print("Release signing checks passed. Temporary keys and validation APKs are not retained.", flush=True)
        finally:
            # Restore preexisting outputs; do not leave an APK signed with a throwaway key.
            for artifact in artifacts:
                if artifact in backups:
                    shutil.copy2(backups[artifact], artifact)
                else:
                    artifact.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
