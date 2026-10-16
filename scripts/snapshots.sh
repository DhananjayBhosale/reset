#!/bin/zsh
# UI snapshot tests: draw key views with fixed numbers and compare them with Fixtures/snapshots.
#
#   ./scripts/snapshots.sh            compare (also runs as part of ./scripts/test.sh)
#   ./scripts/snapshots.sh --record   rewrite the references from the current code (review them before committing!)
#
# On a failure, the actual image and a diff (changed pixels in red) are in $TMPDIR/reset-snapshots/failed.
set -e
set -o pipefail
cd "$(dirname "$0")/.."

if [[ -z "$DEVELOPER_DIR" && -d "$HOME/Desktop/Kahipan/Xcode-beta.app" ]]; then
  DEVELOPER_DIR="$HOME/Desktop/Kahipan/Xcode-beta.app/Contents/Developer"
fi
[[ -n "$DEVELOPER_DIR" ]] && export DEVELOPER_DIR

case "$1" in
  "") ;;
  --record) export TEST_RUNNER_RESET_RECORD_SNAPSHOTS=1 ;;
  *) echo "usage: $0 [--record]" >&2; exit 2 ;;
esac

OUT="$(getconf DARWIN_USER_TEMP_DIR)reset-snapshots"
rm -rf "$OUT"
xcodegen generate --quiet
rc=0
xcodebuild test -project Reset.xcodeproj -scheme Reset -configuration Debug -derivedDataPath "$HOME/Library/Caches/Reset/TestDerived" \
  -destination 'platform=macOS' -only-testing:ResetTests/SnapshotTests CODE_SIGN_IDENTITY=- 2>&1 \
  | grep -E "\.swift:[0-9]+:[0-9]+: error:|Snapshot .* changed|No reference|Actual:|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | grep -v "Test Suite" || rc=$?

if [[ -n "$TEST_RUNNER_RESET_RECORD_SNAPSHOTS" ]]; then
  if [[ $rc -eq 0 && -d "$OUT/recorded" ]]; then
    mkdir -p Fixtures/snapshots
    rsync -a "$OUT/recorded/" Fixtures/snapshots/
    echo "References rewritten: $(ls Fixtures/snapshots | wc -l | tr -d ' ') images. Review with: git status Fixtures/snapshots"
  fi
  exit $rc
fi
[[ $rc -ne 0 && -d "$OUT/failed" ]] && echo "Actual and diff images: $OUT/failed"
exit $rc
