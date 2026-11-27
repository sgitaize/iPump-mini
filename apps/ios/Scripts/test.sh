#!/bin/sh
# Runs all tests in sequence: MiniMedKit (swift test), then the iOS unit tests in the simulator.
#   apps/ios/Scripts/test.sh            everything
#   SIM_UDID=<udid> ...                 other simulator (default: iPhone 17)
#   SKIP_CORE=1 / SKIP_IOS=1            only one part
set -eu

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SIM_UDID="${SIM_UDID:-62562415-F60F-41F2-936A-4C0E828CE899}"
DD="${DERIVED_DATA:-$ROOT/apps/ios/build/dd}"
START=$(date +%s)

if [ "${SKIP_CORE:-0}" != "1" ]; then
  echo "== MiniMedKit (swift test) =="
  CORE_LOG="$(mktemp)"
  if (cd "$ROOT/core/MiniMedKit" && swift test >"$CORE_LOG" 2>&1); then
    grep -E "Executed [0-9]+ tests" "$CORE_LOG" | tail -1
  else
    grep -E "error:|failed|Executed [0-9]+ tests" "$CORE_LOG" | tail -30
    echo "FEHLER: swift test (Log: $CORE_LOG)"
    exit 1
  fi
fi

if [ "${SKIP_IOS:-0}" != "1" ]; then
  echo "== iOS-Unit-Tests (Simulator $SIM_UDID) =="
  command -v xcodegen >/dev/null || { echo "xcodegen fehlt (brew install xcodegen)"; exit 1; }
  (cd "$ROOT/apps/ios" && xcodegen generate >/dev/null)
  xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
  LOG="$(mktemp)"
  if xcodebuild test -project "$ROOT/apps/ios/OpenMinipump.xcodeproj" -scheme OpenMinipump \
      -destination "platform=iOS Simulator,id=$SIM_UDID" -derivedDataPath "$DD" >"$LOG" 2>&1; then
    grep -E "Executed [0-9]+ tests" "$LOG" | tail -1
  else
    grep -E "error:|failed|Executed [0-9]+ tests" "$LOG" | tail -30
    echo "FEHLER: iOS-Tests (Log: $LOG)"
    exit 1
  fi
fi

echo "Alles grün ($(( $(date +%s) - START )) s)"
