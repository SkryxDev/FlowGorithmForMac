#!/usr/bin/env python3
# FlowGorithmForMac · Copyright © 2026 SkryxDev
# GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

"""Rebuilds FlowGorithmForMac/Localizable.xcstrings from the strings the compiler extracted.

Xcode keeps the catalog in sync when building in the IDE; command-line builds don't,
so this script does it: build first, then run

    python3 Scripts/sync-strings.py build/DerivedData

Italian translations live in Scripts/translations-it.json. Keys without a translation
are listed, so nothing is silently left in English.
"""
import glob
import json
import os
import re
import sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
derived = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "build", "DerivedData")
catalog_path = os.path.join(root, "FlowGorithmForMac", "Localizable.xcstrings")
translations = json.load(open(os.path.join(root, "Scripts", "translations-it.json"), encoding="utf-8"))

keys = set()
pattern = os.path.join(derived, "Build", "Intermediates.noindex", "FlowGorithmForMac.build", "*", "FlowGorithmForMac.build", "Objects-normal", "*", "*.stringsdata")
for path in glob.glob(pattern):
    data = json.load(open(path, encoding="utf-8"))
    for entries in data.get("tables", {}).values():
        for entry in entries:
            keys.add(entry["key"])


def needs_translation(key):
    """Example values and symbols ("age", "%lld", "—") are shown as they are."""
    if key in translations:
        return True
    letters = re.sub(r"%(\d+\$)?(lld|@|%)", "", key)
    return bool(re.search(r"[A-Za-z]{3,}", letters)) and " " in key.strip()


strings = {}
missing = []
for key in sorted(keys):
    if key == "":
        continue
    if key in translations:
        strings[key] = {
            "localizations": {
                "it": {"stringUnit": {"state": "translated", "value": translations[key]}}
            }
        }
    else:
        strings[key] = {"shouldTranslate": False}
        if needs_translation(key):
            missing.append(key)

catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
with open(catalog_path, "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
    f.write("\n")

print(f"{len(strings)} strings, {len(strings) - len([k for k in strings if 'shouldTranslate' in strings[k]])} translated")
for key in missing:
    print("missing:", key)
