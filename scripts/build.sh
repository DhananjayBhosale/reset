#!/bin/zsh
# Build Reset.app into ./build.
#
#   ./scripts/build.sh              ad-hoc signed build (everything except widgets)
#   TEAM=ABCDE12345 ./scripts/build.sh --install
#                                   signed with your Apple Development certificate, so the widgets show up
#
# --install copies the app to /Applications and launches it.
# Needs Xcode 16 or later and XcodeGen (brew install xcodegen).
set -e
cd "$(dirname "$0")/.."

# Use DEVELOPER_DIR if you set it (for an Xcode outside /Applications); otherwise xcode-select decides.
[[ -n "$DEVELOPER_DIR" ]] && export DEVELOPER_DIR

xcodegen generate --quiet

SIGNING=()
if [[ -n "$TEAM" ]]; then
  SIGNING=(DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_IDENTITY="Apple Development")
fi

xcodebuild -project Reset.xcodeproj -scheme Reset -configuration "${CONFIG:-Release}" \
  -derivedDataPath build/DerivedData "${SIGNING[@]}" -quiet build
APP="build/DerivedData/Build/Products/${CONFIG:-Release}/Reset.app"
echo "Built: $APP"

if [[ "$1" == "--install" ]]; then
  pkill -x Reset || true
  rm -rf /Applications/Reset.app
  cp -R "$APP" /Applications/
  open /Applications/Reset.app
  echo "Installed to /Applications/Reset.app"
fi
