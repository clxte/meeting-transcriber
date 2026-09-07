#!/usr/bin/env bash
# Enumerates the localization keys the compiler can extract from the app and
# AudioTapLib sources — every SwiftUI string literal and String(localized:)
# call — and optionally lists the ones the French table does not cover yet.
#
# Usage:
#   ./scripts/extract-localizable-keys.sh             # all keys, sorted
#   ./scripts/extract-localizable-keys.sh --missing   # keys with no fr entry
#
# The key list comes from the compiler (-emit-localized-strings), not from
# grep, so interpolations appear exactly as the runtime will look them up
# ("Update Available: %@", "%lld speakers", a literal % as %%). Two kinds of
# key are invisible here by nature and covered elsewhere:
#   - runtime-assembled text passed through Localized.lookup(...) — pinned to
#     the French table by LocalizationTableTests instead;
#   - keys whose French rendering lives in Localizable.stringsdict (plurals) —
#     the --missing check reads that file too.
# A key listed by --missing is not a bug: a missing entry falls back to the
# English literal. It is the to-do list for the next translation pass.
set -euo pipefail
cd "$(dirname "$0")/.."

SPM_DIR="app/MeetingTranscriber"
STRINGSDATA_DIR="$SPM_DIR/.build/stringsdata"
mkdir -p "$STRINGSDATA_DIR"
(cd "$SPM_DIR" && swift build \
    -Xswiftc -emit-localized-strings \
    -Xswiftc -emit-localized-strings-path -Xswiftc "$PWD/.build/stringsdata" >&2)

python3 - "$@" <<'PYEOF'
import glob
import json
import plistlib
import re
import sys

missing_only = "--missing" in sys.argv

keys = set()
for path in glob.glob("app/MeetingTranscriber/.build/stringsdata/*.stringsdata"):
    with open(path) as f:
        data = json.load(f)
    src = data.get("source", "")
    if "/app/MeetingTranscriber/Sources/" not in src \
            and "/tools/audiotap/Sources/" not in src:
        continue
    for entries in data.get("tables", {}).values():
        keys.update(e["key"] for e in entries)

if missing_only:
    def unescape(s):
        return re.sub(
            r"\\(.)",
            lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)),
            s,
        )

    covered = set()
    strings_path = "app/MeetingTranscriber/Localization/fr.lproj/Localizable.strings"
    with open(strings_path, encoding="utf-8") as f:
        table = f.read()
    covered.update(
        unescape(k) for k in re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=', table, re.M)
    )
    try:
        dict_path = "app/MeetingTranscriber/Localization/fr.lproj/Localizable.stringsdict"
        with open(dict_path, "rb") as f:
            covered.update(plistlib.load(f).keys())
    except FileNotFoundError:
        pass
    keys -= covered

for key in sorted(keys):
    print(key)
PYEOF
