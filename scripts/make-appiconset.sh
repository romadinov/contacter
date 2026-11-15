#!/bin/bash
# Renders scripts/make-icon.swift into App/Assets.xcassets/AppIcon.appiconset. Run after changing the icon.
set -euo pipefail
cd "$(dirname "$0")/.."
SET=App/Assets.xcassets/AppIcon.appiconset
mkdir -p build/tmp "$SET"
swiftc -O scripts/make-icon.swift -o build/tmp/make-icon
build/tmp/make-icon build/tmp/icon-1024.png

images=""
for pt in 16 32 128 256 512; do
    for scale in 1 2; do
        px=$((pt * scale))
        name="icon_${pt}x${pt}@${scale}x.png"
        sips -z $px $px build/tmp/icon-1024.png --out "$SET/$name" >/dev/null
        images+="{\"idiom\":\"mac\",\"size\":\"${pt}x${pt}\",\"scale\":\"${scale}x\",\"filename\":\"$name\"},"
    done
done
echo "{\"images\":[${images%,}],\"info\":{\"version\":1,\"author\":\"xcode\"}}" > "$SET/Contents.json"
echo '{"info":{"version":1,"author":"xcode"}}' > App/Assets.xcassets/Contents.json
echo "Wrote $SET"
