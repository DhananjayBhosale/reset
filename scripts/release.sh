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

if [[ -n "$IDENTITY" ]]; then
  TEAMID=$(echo "$IDENTITY" | sed 's/.*(\(.*\)).*/\1/')
  xcodebuild -project Reset.xcodeproj -scheme Reset -configuration Release -derivedDataPath build/ReleaseDerived \
    DEVELOPMENT_TEAM="$TEAMID" CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp" -quiet build
else
  xcodebuild -project Reset.xcodeproj -scheme Reset -configuration Release -derivedDataPath build/ReleaseDerived -quiet build
fi

cp -R build/ReleaseDerived/Build/Products/Release/Reset.app "$OUT/"
ZIP="$OUT/Reset-$VERSION.zip"
ditto -c -k --keepParent "$OUT/Reset.app" "$ZIP"

if [[ -n "$IDENTITY" && -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUT/Reset.app"
  rm "$ZIP"; ditto -c -k --keepParent "$OUT/Reset.app" "$ZIP"
fi
echo "Release: $ZIP"
