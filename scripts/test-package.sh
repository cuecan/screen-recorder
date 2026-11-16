#!/bin/bash
# Builds CueCanKit and runs its tests, and stops them if they run too long.
#
# A stalled test prints nothing, so a run that only timed out says nothing about where it stopped. When
# the tests pass TEST_LIMIT seconds, this prints what every thread of the test process is doing, ends
# the run and fails.
#
# There are two suites:
#   full   every test. Run it on a Mac before a change is merged: many tests write and read real video
#          and sound, which needs a real Mac's hardware.
#   quick  the test targets that need no media: the project and edit model, and the transcript logic.
#          This is what runs on a pull request, where the machine is a virtual one.
#
#   scripts/test-package.sh            # full, with 300 seconds for the tests themselves
#   scripts/test-package.sh quick
#   TEST_LIMIT=60 scripts/test-package.sh
set -euo pipefail

limit="${TEST_LIMIT:-300}"
suite="${1:-full}"
# A test target joins the quick suite once it's known to need no media and to pass on a virtual machine.
quick_targets='ProjectKitTests|TranscribeKitTests'
case "$suite" in
    full) filter=() ;;
    quick) filter=(--filter "^($quick_targets)\\.") ;;
    *) echo "Unknown suite \"$suite\". Use full or quick." >&2; exit 2 ;;
esac
cd "$(dirname "$0")/../Packages/CueCanKit"

# Building has no limit here: it is the tests that stall, and the build's length depends on the cache.
swift build --build-tests

swift test --skip-build ${filter[@]+"${filter[@]}"} &
tests=$!

waited=0
while kill -0 "$tests" 2>/dev/null; do
    if [ "$waited" -ge "$limit" ]; then
        echo "The tests have run for $limit seconds. What the test process is doing:" >&2
        for process in $(pgrep -f 'swiftpm-testing-helper|xctest' || true); do
            report="$(mktemp)"
            # Two seconds of samples is enough to tell a thread that is waiting from one that is working.
            sample "$process" 2 -file "$report" > /dev/null 2>&1 || continue
            # The call graph only: the binary image list after it is long and says nothing here.
            sed -n '/^Call graph:/,/^Total number in stack/p' "$report" | awk 'NR <= 1500' >&2
            rm -f "$report"
        done
        # The runner first, so it can't start the next target's tests after its helper is stopped.
        kill "$tests" 2>/dev/null || true
        pkill -f 'swiftpm-testing-helper|xctest' || true
        exit 1
    fi
    sleep 5
    waited=$((waited + 5))
done
wait "$tests"
