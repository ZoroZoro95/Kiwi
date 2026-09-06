#!/bin/bash
set -euo pipefail

# Run from any directory. No paid signing identity or notarization credentials.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
release_version="0.1.0"
release_work="$(mktemp -d /tmp/free-touch-package.XXXXXX)"
release_name="Free-Touch-${release_version}-macOS-arm64-unnotarized"
release_folder="$release_work/$release_name"
mkdir -p "$release_folder" "$project_root/dist"

xcodebuild -quiet \
  -project "$project_root/TrackpadCanvas/TrackpadCanvas.xcodeproj" \
  -scheme TrackpadCanvas -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$release_work/DerivedData" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  PRODUCT_NAME="Free Touch" PRODUCT_MODULE_NAME=TrackpadCanvas \
  MARKETING_VERSION="$release_version" CURRENT_PROJECT_VERSION=1 \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build

ditto "$release_work/DerivedData/Build/Products/Release/Free Touch.app" "$release_folder/Free Touch.app"
cp "$project_root/docs/PRERELEASE.md" "$release_folder/START-HERE.md"
cp "$project_root/LICENSE" "$release_folder/LICENSE.txt"
cp "$project_root/TrackpadCanvas/MathJax-LICENSE.txt" "$release_folder/MathJax-LICENSE.txt"

codesign --verify --deep --strict "$release_folder/Free Touch.app"
lipo -archs "$release_folder/Free Touch.app/Contents/MacOS/Free Touch"
ditto -c -k --sequesterRsrc --keepParent "$release_folder" "$project_root/dist/$release_name.zip"
(cd "$project_root/dist" && shasum -a 256 "$release_name.zip" > "$release_name.sha256")
printf 'Package: %s\nChecksum: %s\nBuild workspace: %s\n' \
  "$project_root/dist/$release_name.zip" "$project_root/dist/$release_name.sha256" "$release_work"
