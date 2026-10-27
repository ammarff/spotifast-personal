#!/bin/bash
# Build the optional Pock widget against the framework in the installed Pock app.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
pock_app="${POCK_APP:-/Applications/Pock.app}"
frameworks="$pock_app/Contents/Frameworks"
output="${1:-$here/build/SpotifastLyrics.pock}"
sdk="${SPOTIFAST_POCK_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"

if [[ ! -d "$frameworks/PockKit.framework" ]]; then
    echo "PockKit.framework was not found in $frameworks" >&2
    exit 1
fi

mkdir -p "$output/Contents/MacOS"
mkdir -p "$here/build/module-cache"
cp "$here/Info.plist" "$output/Contents/Info.plist"
swiftc -sdk "$sdk" -module-cache-path "$here/build/module-cache" \
    -emit-library -Xlinker -bundle -module-name SpotifastLyrics \
    -F "$frameworks" -framework PockKit \
    -Xlinker -rpath -Xlinker "$frameworks" \
    "$here/SpotifastLyrics.swift" \
    -o "$output/Contents/MacOS/SpotifastLyrics"
codesign --force --sign - "$output"
echo "$output"
