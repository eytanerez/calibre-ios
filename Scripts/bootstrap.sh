#!/bin/bash
# Regenerate the Xcode project after checkout or project.yml changes.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
echo "Generated Calibre.xcodeproj — open it or build with:"
echo "  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Calibre.xcodeproj -scheme Calibre -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build"
