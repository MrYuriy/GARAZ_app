#!/usr/bin/env bash
# Build the release APK that talks to the production server.
#
#   ./scripts/build_apk.sh                       # https://garaz.piatek-magazyn.com
#   API_BASE_URL=https://other/api ./scripts/build_apk.sh
#
# Signed with the key android/key.properties points at (kept outside the repo);
# without it the APK is debug-signed and the QR links will not open it.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"

if [ ! -f android/key.properties ]; then
  echo "WARNING: android/key.properties missing — the APK will be signed with the debug key." >&2
fi

flutter build apk --release --dart-define=API_BASE_URL="${API_BASE_URL:-https://garaz.piatek-magazyn.com/api}"

version="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
out="build/garaz-${version%%+*}.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$out"
echo "APK: $here/$out"
