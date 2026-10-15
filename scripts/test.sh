#!/bin/zsh
# Run the unit tests: cost maths, de-duplication, window estimates, forecast, project grouping.
set -e
cd "$(dirname "$0")/.."
[[ -n "$DEVELOPER_DIR" ]] && export DEVELOPER_DIR
xcodegen generate --quiet
xcodebuild test -project Reset.xcodeproj -scheme Reset -configuration Debug -derivedDataPath build/TestDerived \
  -destination 'platform=macOS' CODE_SIGN_IDENTITY=- 2>&1 \
  | grep -E "error:|passed \(|failed \(|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | grep -v "Test Suite"
