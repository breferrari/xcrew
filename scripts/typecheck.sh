#!/bin/sh
# Type-checks the mod against the API types Claude Code writes into .claude-plugin/types/ when a
# session loads it. They are gitignored (they list the MCP tools connected on this machine), and no
# command writes them without a session, so CI can't run this; run it before pushing a mod change.
set -eu
cd "$(dirname "$0")/.."
if [ ! -f .claude-plugin/types/claude-code/index.d.ts ]; then
  echo "typecheck: no API types yet. Start 'claude --plugin-dir .' here once, then rerun." >&2
  exit 1
fi
exec npx --yes --package typescript@5.6.3 tsc -p . --noEmit
