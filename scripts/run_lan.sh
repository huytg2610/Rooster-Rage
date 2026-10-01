#!/usr/bin/env bash
# Build the web client and start the LAN host.
# Phones on the same WiFi open the printed URL (or scan the QR).
#   scripts/run_lan.sh            # port 8080
#   scripts/run_lan.sh -p 9000    # custom port
#   SKIP_BUILD=1 scripts/run_lan.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  (cd "$ROOT/app" && flutter build web --release --wasm --no-web-resources-cdn)
fi
cd "$ROOT/server"
dart pub get >/dev/null
exec dart run bin/server.dart --web "$ROOT/app/build/web" "$@"
