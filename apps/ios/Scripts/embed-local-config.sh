#!/bin/sh
# Copies local, gitignored configuration into the app bundle at build time:
#   - DEV_MODE / TEST_PUMP_SERIAL from <repo>/.env  -> DevConfig.plist
#   - SAKE key database from <repo>/_vendor/keys/   -> mobile-pump.keydb.hex
# Nothing of this is committed (clean room, hard rules 2–4).
set -eu

REPO="${SRCROOT}/../.."
DEST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
mkdir -p "$DEST"

DEV_MODE=1
TEST_PUMP_SERIAL=""
# Public builds (CI, OMP_PUBLIC_BUILD=1) never take local files: no .env, no key database.
# Their DEV_MODE comes from OMP_PUBLIC_DEV_MODE (default 1 = locked to no pump).
PUBLIC="${OMP_PUBLIC_BUILD:-0}"
if [ "$PUBLIC" = "1" ]; then
  DEV_MODE="${OMP_PUBLIC_DEV_MODE:-1}"
  echo "note: public build, DEV_MODE=$DEV_MODE, no key database embedded"
elif [ -f "$REPO/.env" ]; then
  v=$(grep -E '^DEV_MODE=' "$REPO/.env" | tail -1 | cut -d= -f2- | tr -d '"'"'"' \r' || true)
  [ -n "$v" ] && DEV_MODE="$v"
  TEST_PUMP_SERIAL=$(grep -E '^TEST_PUMP_SERIAL=' "$REPO/.env" | tail -1 | cut -d= -f2- | tr -d '"'"'"' \r' || true)
else
  echo "warning: .env fehlt – DEV_MODE=1 ohne Testpumpe, jede Pumpe wird abgelehnt."
fi

if [ "$DEV_MODE" = "1" ]; then DEV_BOOL=true; else DEV_BOOL=false; fi
cat > "$DEST/DevConfig.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>DEV_MODE</key><${DEV_BOOL}/>
  <key>TEST_PUMP_SERIAL</key><string>${TEST_PUMP_SERIAL}</string>
</dict>
</plist>
EOF

KEYDB="$REPO/_vendor/keys/mobile-pump.keydb.hex"
if [ "$PUBLIC" = "1" ]; then
  rm -f "$DEST/mobile-pump.keydb.hex"
elif [ -f "$KEYDB" ]; then
  cp "$KEYDB" "$DEST/mobile-pump.keydb.hex"
else
  rm -f "$DEST/mobile-pump.keydb.hex"
  echo "warning: Schlüsseldatenbank fehlt ($KEYDB) – die App kann keinen SAKE-Handshake durchführen. Siehe docs/setup-ios.md"
fi
