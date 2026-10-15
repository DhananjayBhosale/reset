#!/bin/zsh
# Package Reset for a GitHub release.
#
#   ./scripts/release.sh
#       Ad-hoc signed zip. People open it with right-click > Open the first time. No widgets.
#
#   IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=reset ./scripts/release.sh
#       Developer ID signed, notarized and stapled. Opens without warnings, widgets work.
#       One-time setup: xcrun notarytool store-credentials reset --apple-id you@example.com --team-id TEAMID
set -e
cd "$(dirname "$0")/.."
VERSION=$(grep MARKETING_VERSION project.yml | head -1 | sed 's/.*"\(.*\)".*/\1/')
xcodegen generate --quiet
OUT=build/release
rm -rf "$OUT" build/ReleaseDerived; mkdir -p "$OUT"

# Strip debug symbols from the shipped binaries (Xcode only does this for archives) and write source paths
# relative to the repo, so the download doesn't carry the build machine's home folder.
CLEAN=(DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES STRIP_STYLE=non-global
       OTHER_SWIFT_FLAGS="-file-prefix-map $PWD=.")

if [[ -n "$IDENTITY" ]]; then
  TEAMID=$(echo "$IDENTITY" | sed 's/.*(\(.*\)).*/\1/')
  xcodebuild -project Reset.xcodeproj -scheme Reset -configuration Release -derivedDataPath build/ReleaseDerived \
    DEVELOPMENT_TEAM="$TEAMID" CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp" "${CLEAN[@]}" -quiet build
else
  xcodebuild -project Reset.xcodeproj -scheme Reset -configuration Release -derivedDataPath build/ReleaseDerived "${CLEAN[@]}" -quiet build
fi

cp -R build/ReleaseDerived/Build/Products/Release/Reset.app "$OUT/"
ZIP="$OUT/Reset-$VERSION.zip"
ditto -c -k --keepParent "$OUT/Reset.app" "$ZIP"

if [[ -n "$IDENTITY" && -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUT/Reset.app"
  rm "$ZIP"; ditto -c -k --keepParent "$OUT/Reset.app" "$ZIP"
fi
# Disk image: Reset.app next to an Applications shortcut, for drag-to-install.
DMG="$OUT/Reset-$VERSION.dmg"
STAGE="$OUT/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$OUT/Reset.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Reset" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
rm -rf "$STAGE"
if [[ -n "$IDENTITY" ]]; then
  codesign --sign "$IDENTITY" --timestamp "$DMG"
  if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
fi

echo "Release: $ZIP"
echo "Release: $DMG"
