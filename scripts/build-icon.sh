#!/bin/sh
# Rebuild the native icon representations from the approved source artwork.
set -eu
cd "$(dirname "$0")/.."
iconset="$PWD/.build/PerformanceDaddy.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Sources/PerformanceDaddy/Resources/PerformanceDaddy.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Sources/PerformanceDaddy/Resources/PerformanceDaddy.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o Support/PerformanceDaddy.icns
