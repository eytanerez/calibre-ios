#!/bin/bash
# Regenerate the Xcode project after checkout or when files are added.
# Safe under concurrent callers (parallel agents): a simple mkdir spin-lock
# serializes xcodegen runs.
set -euo pipefail
cd "$(dirname "$0")/.."

LOCK=/tmp/calibre-xcodegen.lock
for i in $(seq 1 60); do
  if mkdir "$LOCK" 2>/dev/null; then
    trap 'rmdir "$LOCK"' EXIT
    break
  fi
  sleep 1
done
[ -d "$LOCK" ] || { echo "could not acquire xcodegen lock"; exit 1; }

xcodegen generate -q
echo "Generated Calibre.xcodeproj"
