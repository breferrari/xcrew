#!/bin/sh
# Fails when MobileBuildMCP, started through the plugin's launcher, doesn't register a tool xcrew counts on: each tool of
# the `sim-env` group in the config setup wrote, and each session tool the routing and skills name. Or when it
# registers one of the `xcode-ide` bridge's, which forwards Xcode MCP tools around the mod (docs/findings.md,
# *MobileBuildMCP's tool groups*). The server's log names its groups, not their tools, so this asks it for `tools/list`.
# scripts/registered-tools.sh <project with a config setup wrote>
set -eu
cd "$(dirname "$0")/.."
project=$1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
awk '/^  sim-env:$/ { inside = 1; next } inside && /^    - / { print substr($0, 7); next } { inside = 0 }' "$project/.mobilebuildmcp/config.yaml" > "$work/wanted"
grep -rhoE 'session_[a-z_]+' context skills >> "$work/wanted"
sort -u -o "$work/wanted" "$work/wanted"
if ! grep -q . "$work/wanted"; then
  echo "registered-tools.sh: the config names no sim-env tools" >&2
  exit 1
fi
# The server answers on standard output while its input stays open; it exits once the input closes.
{
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"xcrew-canary","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  sleep 6
} | libexec/mobilebuildmcp-server "$project" 2> "$work/log" | grep '"id":2' | grep -oE '"name":"[A-Za-z0-9_]+"' | sed 's/^"name":"//; s/"$//' | sort -u > "$work/listed" || true
if ! grep -q . "$work/listed"; then
  echo "registered-tools.sh: MobileBuildMCP listed no tools" >&2
  cat "$work/log" >&2
  exit 1
fi
missing=$(comm -23 "$work/wanted" "$work/listed")
if [ -n "$missing" ]; then
  echo "registered-tools.sh: MobileBuildMCP doesn't register: $(echo "$missing" | tr '\n' ' ')" >&2
  exit 1
fi
if grep -E '^xcode_(ide|tools)_' "$work/listed" >&2; then
  echo "registered-tools.sh: MobileBuildMCP registers the xcode-ide bridge's tools" >&2
  exit 1
fi
