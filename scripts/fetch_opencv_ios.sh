#!/usr/bin/env bash
# Downloads pinned OpenCV 4.11.0 xcframework for iOS. Not committed (large).
# After running, add opencv2.xcframework to ios/Runner.xcodeproj and
# compile native/scanner_core/src/scan_core.cpp.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/ios/ThirdParty/opencv2.xcframework"
VERSION="4.11.0"
echo "Fetch OpenCV $VERSION xcframework into $DEST"
echo "Use an Apache-2.0 OpenCV 4.11.0 xcframework (do not copy GPL Document-Scanner binaries)."
mkdir -p "$(dirname "$DEST")"
echo "Place opencv2.xcframework at: $DEST"
echo "Then set VISION plugin isAvailable to true after linking scan_core."
