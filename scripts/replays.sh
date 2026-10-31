#!/bin/sh
# Rewrites hooks/mod/replays.ts: each raw MobileBuildMCP capture of the test bed as the mod gets it, and what `xcrew report`
# answers for it with no result bundle to read. TestbedReplayTests writes it and holds each answer to the CLI and to
# MobileBuildMCP's own counts, so a changed golden shows in the diff.
# scripts/replays.sh [<test bed>]   the test bed defaults to XCREW_TESTBED, else the clone beside this repository
set -eu
exec < /dev/null
cd "$(dirname "$0")/.."
if [ $# -gt 0 ]; then XCREW_TESTBED=$1; export XCREW_TESTBED; fi
XCREW_RECORD_REPLAYS=1 swift test --filter 'TestbedReplayTests/record' > /dev/null 2>&1 || { echo "the recording failed: run XCREW_RECORD_REPLAYS=1 swift test --filter TestbedReplayTests/record" >&2; exit 1; }
echo hooks/mod/replays.ts
