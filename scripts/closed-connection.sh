#!/bin/sh
# Fails when the installed Claude Code words an MCP call whose connection closed so that xcrew no longer notes it: the
# error is built from the executable's own template and code.
# scripts/closed-connection.sh <Claude Code's executable>
set -eu
cd "$(dirname "$0")/.."
error=$(perl -0777 -ne '
  exit 2 unless /ConnectionClosed,"Connection closed"\)/;
  if (/`(MCP error \$\{\w+\}: \$\{\w+\})`/) { my $t = $1; $t =~ s/\$\{\w+\}/-32000/; $t =~ s/\$\{\w+\}/Connection closed/; print $t; exit 0 }
  exit 1' "$1") || {
  echo "Claude Code's executable no longer raises an MCP error \"Connection closed\" from its own template: xcrew notes a closed Xcode MCP connection by those words, so read the new error and update ClosedConnection and scripts/closed-connection.sh" >&2
  exit 1
}
printf '%s' "$error" | bin/xcrew note --server xcode --error | grep -qF '/mcp' && exit 0
echo "xcrew didn't note an Xcode MCP call whose connection closed, which Claude Code now words \"$error\": check ClosedConnection against it" >&2
exit 1
