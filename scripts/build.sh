#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.0.0}"
APP="dist/息眠.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build

swiftc -O -parse-as-library -swift-version 6 -target arm64-apple-macosx14.0 \
  Sources/PowerCore.swift Sources/PowerModel.swift Sources/MacSleepControl.swift \
  -o .build/MacSleepControl-arm64 -framework SwiftUI -framework AppKit -framework IOKit
if [[ "${UNIVERSAL:-1}" == "1" ]]; then
  swiftc -O -parse-as-library -swift-version 6 -target x86_64-apple-macosx14.0 \
    Sources/PowerCore.swift Sources/PowerModel.swift Sources/MacSleepControl.swift \
    -o .build/MacSleepControl-x86_64 -framework SwiftUI -framework AppKit -framework IOKit
  lipo -create .build/MacSleepControl-arm64 .build/MacSleepControl-x86_64 -output "$APP/Contents/MacOS/MacSleepControl"
else
  cp .build/MacSleepControl-arm64 "$APP/Contents/MacOS/MacSleepControl"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MacSleepControl</string>
<key>CFBundleIdentifier</key><string>io.github.cut-hand.MacSleepControl</string>
<key>CFBundleName</key><string>息眠</string>
<key>CFBundleDisplayName</key><string>息眠</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 cut-hand. MIT License.</string>
</dict></plist>
PLIST
swift scripts/Icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/MacSleepControl-$VERSION-macOS.zip"
(cd dist && shasum -a 256 "MacSleepControl-$VERSION-macOS.zip" > SHA256SUMS.txt)
echo "Built $APP"
