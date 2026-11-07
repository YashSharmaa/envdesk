#!/bin/bash
# Builds envdesk.app. Usage: ./build.sh            -> ~/Applications/envdesk.app
#                            ./build.sh /Applications
set -euo pipefail
cd "$(dirname "$0")"
dest="${1:-$HOME/Applications}"
app="$dest/envdesk.app"
mkdir -p "$dest"; rm -rf "$app"; mkdir -p "$app/Contents/MacOS"
mkdir -p .build/icon && cp scripts/make-icon.swift .build/icon/main.swift
swiftc -O .build/icon/main.swift Logo.swift -o .build/make-icon && .build/make-icon
swiftc -O -parse-as-library Sources.swift Logo.swift -o "$app/Contents/MacOS/envdesk"
mkdir -p "$app/Contents/Resources" && cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>envdesk</string>
<key>CFBundleIdentifier</key><string>dev.envdesk.app</string>
<key>CFBundleExecutable</key><string>envdesk</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force -s - "$app"
echo "Built $app"
