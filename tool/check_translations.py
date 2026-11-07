#!/usr/bin/env python3
"""Check locale parity and literal .tr() keys without Flutter dependencies."""
import json
import re
from pathlib import Path


def main():
    root = Path(__file__).resolve().parent.parent
    locales = {
        file.stem: json.loads(file.read_text(encoding="utf-8"))
        for file in sorted((root / "assets/lang").glob("*.json"))
    }
    expected = {"en", "es", "ru", "fr", "de", "it", "pt"}
    if set(locales) != expected:
        raise SystemExit(f"Unexpected locale set: {sorted(locales)}")
    keys = set(locales["en"])
    errors = []
    for locale, values in locales.items():
        if set(values) != keys:
            errors.append(f"{locale}: missing={sorted(keys - set(values))}; extra={sorted(set(values) - keys)}")
        if any(not isinstance(value, str) or not value.strip() for value in values.values()):
            errors.append(f"{locale}: translations must be nonempty strings")
    pattern = re.compile(r"['\"]([^'\"\n]+)['\"]\.tr\(")
    for file in sorted((root / "lib").rglob("*.dart")):
        missing = set(pattern.findall(file.read_text(encoding="utf-8"))) - keys
        if missing:
            errors.append(f"{file.relative_to(root)}: unknown keys {sorted(missing)}")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"Translations OK: {len(locales)} locales, {len(keys)} keys each")


if __name__ == "__main__":
    main()
