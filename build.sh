#!/bin/bash
# Builds CaffeineOSS.app (universal: Apple silicon + Intel).
#
#   ./build.sh            sign with your Developer ID if one is in the keychain, else ad-hoc
#   SIGN_ID=- ./build.sh  force ad-hoc signing
#   ./build.sh --zip      also produce CaffeineOSS-<version>.zip for distribution
set -euo pipefail
cd "$(dirname "$0")"

VERSION="2.0.0"
APP="CaffeineOSS.app"
MIN_OS="13.0"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling (arm64 + x86_64)…"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 6 -target "$arch-apple-macos$MIN_OS" main.swift -o "/tmp/caffeineoss-$arch.$$"
done
lipo -create /tmp/caffeineoss-{arm64,x86_64}.$$ -output "$APP/Contents/MacOS/CaffeineOSS"
rm -f /tmp/caffeineoss-{arm64,x86_64}.$$

cp assets/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>               <string>CaffeineOSS</string>
  <key>CFBundleDisplayName</key>        <string>CaffeineOSS</string>
  <key>CFBundleIdentifier</key>         <string>com.karimbacchus.caffeineoss</string>
  <key>CFBundleVersion</key>            <string>$VERSION</string>
  <key>CFBundleShortVersionString</key> <string>$VERSION</string>
  <key>CFBundlePackageType</key>        <string>APPL</string>
  <key>CFBundleExecutable</key>         <string>CaffeineOSS</string>
  <key>CFBundleIconFile</key>           <string>AppIcon</string>
  <key>LSApplicationCategoryType</key>  <string>public.app-category.utilities</string>
  <key>LSUIElement</key>                <true/>
  <key>LSMinimumSystemVersion</key>     <string>$MIN_OS</string>
  <key>NSHumanReadableCopyright</key>   <string>MIT License</string>
</dict>
</plist>
PLIST

SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)}"
if [[ -n "$SIGN_ID" && "$SIGN_ID" != "-" ]]; then
  echo "Signing with: $SIGN_ID"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
  echo "Ad-hoc signing…"
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"

if [[ "${1:-}" == "--zip" ]]; then
  ZIP="CaffeineOSS-$VERSION.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Packaged: $(pwd)/$ZIP"
fi

echo "Built: $(pwd)/$APP"
