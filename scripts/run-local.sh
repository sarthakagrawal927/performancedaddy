#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if pgrep -x PerformanceDaddy >/dev/null; then
    echo "Quit PerformanceDaddy before rebuilding the local app."
    exit 1
fi
swift build --product PerformanceDaddy
bin_path="$(swift build --show-bin-path)"
bundle_path="$PWD/.build/PerformanceDaddy.app"
mkdir -p "$bundle_path/Contents/MacOS" "$bundle_path/Contents/Resources"
# Replace the inode, never rewrite executable pages in place.
cp "$bin_path/PerformanceDaddy" "$bundle_path/Contents/MacOS/PerformanceDaddy.next"
mv -f "$bundle_path/Contents/MacOS/PerformanceDaddy.next" "$bundle_path/Contents/MacOS/PerformanceDaddy"
cp Support/Info.plist "$bundle_path/Contents/Info.plist"
cp Support/PerformanceDaddy.icns "$bundle_path/Contents/Resources/PerformanceDaddy.icns"
cp -R "$bin_path/PerformanceDaddy_PerformanceDaddy.bundle" "$bundle_path/Contents/Resources/"
open "$bundle_path"
