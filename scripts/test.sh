#!/bin/zsh
# Run the unit tests: cost maths, de-duplication, window estimates, forecast, project grouping.
# Exits non-zero when the build or any test fails.
set -e
set -o pipefail
cd "$(dirname "$0")/.."

# Use DEVELOPER_DIR if you set it; otherwise fall back to a known beta Xcode, then to xcode-select.
if [[ -z "$DEVELOPER_DIR" && -d "$HOME/Desktop/Kahipan/Xcode-beta.app" ]]; then
  DEVELOPER_DIR="$HOME/Desktop/Kahipan/Xcode-beta.app/Contents/Developer"
fi
[[ -n "$DEVELOPER_DIR" ]] && export DEVELOPER_DIR

xcodegen generate --quiet
# The test copy of the app is built outside the repo: when the repo sits in a protected folder such as Desktop,
# a test app running from there makes macOS ask for access again on every rebuild.
xcodebuild test -project Reset.xcodeproj -scheme Reset -configuration Debug -derivedDataPath "$HOME/Library/Caches/Reset/TestDerived" \
  -destination 'platform=macOS' CODE_SIGN_IDENTITY=- 2>&1 \
  | grep -E "error:|passed \(|failed \(|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | grep -v "Test Suite"
