#!/bin/bash
set -euo pipefail

IOS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$IOS_DIR/.." && pwd)"
BUILD_DIR="$IOS_DIR/build"
PRODUCTS_DIR="$BUILD_DIR/iphoneos"
APP_DIR="$PRODUCTS_DIR/Mumixic.app"
PAYLOAD_DIR="$BUILD_DIR/Payload"
OUT_DIR="${MUMIXIC_IPA_OUTPUT_DIR:-$BUILD_DIR}"
OUT_IPA="$OUT_DIR/Mumixic-iOS-Sideloadly.ipa"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"

mkdir -p "$PRODUCTS_DIR" "$OUT_DIR"
/usr/bin/python3 - "$APP_DIR" <<'PY'
import os, shutil, sys
path = sys.argv[1]
if os.path.exists(path): shutil.rmtree(path)
os.makedirs(path, exist_ok=True)
PY

cp "$IOS_DIR"/Assets.xcassets/AppIcon.appiconset/AppIcon*.png "$APP_DIR/"

xcrun swiftc \
  -swift-version 5 \
  -module-cache-path "$BUILD_DIR/ModuleCache" \
  -sdk "$SDK_PATH" \
  -target arm64-apple-ios17.0 \
  -parse-as-library \
  "$IOS_DIR/Sources/AudioTrack.swift" \
  "$IOS_DIR/Sources/HomeShelf.swift" \
  "$IOS_DIR/Sources/GoogleSessionStore.swift" \
  "$IOS_DIR/Sources/GoogleLoginView.swift" \
  "$IOS_DIR/Sources/YtMusicService.swift" \
  "$IOS_DIR/Sources/LyricsService.swift" \
  "$IOS_DIR/Sources/LocalPlayer.swift" \
  "$IOS_DIR/Sources/MumixicApp.swift" \
  -framework SwiftUI \
  -framework UIKit \
  -framework AVFoundation \
  -framework MediaPlayer \
  -framework WebKit \
  -framework Security \
  -framework UniformTypeIdentifiers \
  -o "$APP_DIR/Mumixic"

/usr/bin/python3 - "$APP_DIR/Info.plist" <<'PY'
import plistlib, sys
info_path = sys.argv[1]
info = {
    "CFBundleDevelopmentRegion": "en",
    "CFBundleDisplayName": "Mumixic",
    "CFBundleExecutable": "Mumixic",
    "CFBundleIdentifier": "com.mumixic.ios",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "Mumixic",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "1.0",
    "CFBundleVersion": "1",
    "CFBundleIcons": {"CFBundlePrimaryIcon": {"CFBundleIconFiles": ["AppIcon-20", "AppIcon-29", "AppIcon-40", "AppIcon-60", "AppIcon-83.5", "AppIcon", "AppIcon~ios-marketing"], "UIPrerenderedIcon": True}},
    "CFBundleIconFiles": ["AppIcon-20", "AppIcon-29", "AppIcon-40", "AppIcon-60", "AppIcon-83.5", "AppIcon", "AppIcon~ios-marketing"],
    "LSRequiresIPhoneOS": True,
    "CFBundleSupportedPlatforms": ["iPhoneOS"],
    "MinimumOSVersion": "17.0",
    "UIDeviceFamily": [1],
    "UIBackgroundModes": ["audio"],
    "UILaunchScreen": {},
    "UIRequiredDeviceCapabilities": ["arm64"],
    "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
    "UIApplicationSupportsIndirectInputEvents": True,
    "UIViewControllerBasedStatusBarAppearance": True,
}
with open(info_path, "wb") as f: plistlib.dump(info, f)
PY

/usr/bin/python3 - "$PAYLOAD_DIR" "$APP_DIR" <<'PY'
import os, shutil, sys
payload, app = sys.argv[1:]
if os.path.exists(payload): shutil.rmtree(payload)
os.makedirs(payload, exist_ok=True)
shutil.copytree(app, os.path.join(payload, "Mumixic.app"))
PY
(
  cd "$BUILD_DIR"
  /usr/bin/ditto -c -k --norsrc --keepParent Payload "$OUT_IPA"
)
echo "Created unsigned iPhone IPA: $OUT_IPA"
echo "Use Sideloadly to sign and install it with your Apple ID."
