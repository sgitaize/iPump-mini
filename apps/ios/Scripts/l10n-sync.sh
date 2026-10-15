#!/bin/sh
# Builds for the simulator and merges all texts into Shared/Localizable.xcstrings.
# Then: python3 Scripts/l10n.py missing  →  translate  →  python3 Scripts/l10n.py apply en.json
set -e
cd "$(dirname "$0")/.."
DD="${TMPDIR:-/tmp}/omp-l10n-dd"
# Clean build so that every source file emits its .stringsdata (otherwise texts of
# unchanged files would be marked stale).
rm -rf "$DD"
xcodebuild -project OpenMinipump.xcodeproj -scheme OpenMinipump -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build -quiet 2>&1 | grep -v IDERunDestination || true
set --
for f in $(find "$DD" -name '*.stringsdata'); do set -- "$@" --stringsdata "$f"; done
xcrun xcstringstool sync Shared/Localizable.xcstrings "$@"
python3 Scripts/l10n.py keys
