#!/usr/bin/env python3
"""Localisation helper for Shared/Localizable.xcstrings (German = source language).

  python3 Scripts/l10n.py keys            add keys used via L10n.tr and texts from MiniMedKit
                                          (pump alarms, sensor messages, modes)
  python3 Scripts/l10n.py missing         print keys without English translation as JSON
  python3 Scripts/l10n.py apply en.json   merge {"German key": "English"} into the catalog

SwiftUI texts are extracted by the compiler (SWIFT_EMIT_LOC_STRINGS) and merged with
`xcrun xcstringstool sync` – see docs/en/translating.md.
"""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Shared/Localizable.xcstrings"
KIT = ROOT.parent.parent / "core/MiniMedKit/Sources/MiniMedKit"


def load():
    return json.loads(CATALOG.read_text())


def save(d):
    # Empty labels (chart values) and pure symbols need no translation.
    for k in ("", "–"):
        if k in d["strings"]:
            d["strings"][k]["shouldTranslate"] = False
    d["strings"] = dict(sorted(d["strings"].items(), key=lambda kv: kv[0].lower()))
    CATALOG.write_text(json.dumps(d, ensure_ascii=False, indent=2, separators=(",", " : ")) + "\n")


def unescape(s):
    return s.encode().decode("unicode_escape").encode("latin-1").decode("utf-8") if "\\" in s else s


def code_keys():
    keys = set()
    tr = re.compile(r'L10n\.tr\(\s*"((?:[^"\\]|\\.)*)"')
    for folder in ["OpenMinipump", "Shared", "Widgets"]:
        for f in (ROOT / folder).rglob("*.swift"):
            keys.update(unescape(m) for m in tr.findall(f.read_text()))
    # Texts from MiniMedKit that the app passes through L10n.tr(...) at runtime.
    alarms = (KIT / "Alarms/PumpAlarms.swift").read_text()
    keys.update(re.findall(r'title: "([^"]+)"', alarms))
    keys.update(re.findall(r'case \.\w+: "([^"]+)"', alarms))
    idd = (KIT / "Protocol/IDDRecords.swift").read_text()
    keys.update(re.findall(r'case (?:0x[0-9A-Fa-f]+|\.\w+): "([^"]+)"', idd))
    return {k for k in keys if k and k != "–"}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "missing"
    d = load()
    strings = d["strings"]
    if cmd == "keys":
        added = 0
        used = code_keys()
        for k in sorted(used):
            if k not in strings:
                strings[k] = {"extractionState": "manual"}
                added += 1
        removed = [k for k, v in strings.items() if v.get("extractionState") == "manual" and k not in used]
        for k in removed:
            del strings[k]
        save(d)
        print(f"{added} keys added, {len(removed)} unused removed, {len(strings)} total")
    elif cmd == "missing":
        out = {k: "" for k, v in strings.items()
               if v.get("shouldTranslate", True) and "en" not in v.get("localizations", {})
               and v.get("extractionState") != "stale"}
        print(json.dumps(out, ensure_ascii=False, indent=1))
    elif cmd == "apply":
        tr = json.loads(pathlib.Path(sys.argv[2]).read_text())
        n = 0
        for k, en in tr.items():
            if not en or k not in strings:
                continue
            strings[k].setdefault("localizations", {})["en"] = {"stringUnit": {"state": "translated", "value": en}}
            n += 1
        save(d)
        print(f"{n} translations applied")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
