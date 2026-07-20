#!/usr/bin/env bash
# Downloads RFIDManager.xcframework if missing (used by Codemagic / fresh clones).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Frameworks/RFIDManager.xcframework"
ZIP="$ROOT/Frameworks/RFIDManager.xcframework.zip"
URL="https://github.com/RFID-Devs/RFID-IOS-SDK/releases/download/v2.0.1/RFIDManager.xcframework.zip"

if [[ -d "$DEST" ]]; then
  echo "RFIDManager.xcframework already present"
  exit 0
fi

mkdir -p "$ROOT/Frameworks"
echo "Downloading RFIDManager.xcframework..."
curl -L --fail --retry 3 -o "$ZIP" "$URL"
unzip -q -o "$ZIP" -d "$ROOT/Frameworks"
rm -f "$ZIP"
echo "RFIDManager.xcframework ready"
