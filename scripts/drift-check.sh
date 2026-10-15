#!/bin/zsh
# Format-drift check: re-parse the anonymised samples in Fixtures/transcripts and compare them with the
# goldens in Fixtures/golden. Exits non-zero on any difference and prints a diff.
#
#   ./scripts/drift-check.sh                    compare
#   ./scripts/drift-check.sh --update-goldens   rewrite the goldens from the current parsers (review the git diff!)
#
# It runs DriftTests from the normal unit suite, so there is one implementation of the check.
set -e
set -o pipefail
cd "$(dirname "$0")/.."

# Use DEVELOPER_DIR if you set it; otherwise fall back to a known beta Xcode, then to xcode-select.
if [[ -z "$DEVELOPER_DIR" && -d "$HOME/Desktop/Kahipan/Xcode-beta.app" ]]; then
  DEVELOPER_DIR="$HOME/Desktop/Kahipan/Xcode-beta.app/Contents/Developer"
fi
[[ -n "$DEVELOPER_DIR" ]] && export DEVELOPER_DIR

case "$1" in
  "") ;;
  --update-goldens) export TEST_RUNNER_RESET_UPDATE_GOLDENS=1 ;;  # xcodebuild passes TEST_RUNNER_* to the tests, prefix removed
  *) echo "usage: $0 [--update-goldens]" >&2; exit 2 ;;
esac

rm -rf build/drift/actual
xcodegen generate --quiet
rc=0
xcodebuild test -project Reset.xcodeproj -scheme Reset -configuration Debug -derivedDataPath build/TestDerived \
  -destination 'platform=macOS' -only-testing:ResetTests/DriftTests CODE_SIGN_IDENTITY=- 2>&1 \
  | grep -E "\.swift:[0-9]+:[0-9]+: error:|Drift in|golden:|actual:|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | grep -v "Test Suite" || rc=$?

if [[ -n "$TEST_RUNNER_RESET_UPDATE_GOLDENS" ]]; then
  [[ $rc -eq 0 ]] && { echo "Goldens rewritten. Review them with: git diff Fixtures/golden"; git status --short Fixtures/golden; }
  exit $rc
fi

if [[ $rc -ne 0 ]]; then
  # Show every difference, not just the first line each test reports.
  if [[ -d build/drift/actual ]]; then
    diff -ru Fixtures/golden build/drift/actual || true
  fi
  echo "Drift check FAILED. See \"When the drift check fails\" in README.md."
fi
exit $rc
