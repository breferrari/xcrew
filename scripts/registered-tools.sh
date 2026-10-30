#!/bin/sh
# Fails when MobileBuildMCP, started through the plugin's launcher, doesn't register a tool xcrew counts on: each tool of
# the `sim-env` group in the config setup wrote, and each session tool the routing, the skills and the mod name in
# backticks. Or when it registers one of the `xcode-ide` bridge's, whose answers the mod can't read (docs/findings.md,
# *MobileBuildMCP's tool groups*). The server's log names its groups, not their tools, so this asks it for `tools/list`.
# scripts/registered-tools.sh <project with a config setup wrote>
set -eu
project=$(cd "$1" && pwd)
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
awk '/^  sim-env:$/ { inside = 1; next } inside && /^    - / { print substr($0, 7); next } { inside = 0 }' "$project/.mobilebuildmcp/config.yaml" > "$work/wanted"
if ! grep -q . "$work/wanted"; then
  echo "registered-tools.sh: the config names no sim-env tools" >&2
  exit 1
fi
# shellcheck disable=SC2016 # the backticks are literal: a tool is named in code spans
grep -rhoE '`session_[a-z_]+`' context skills hooks/mod --include='*.md' --include='*.ts' --exclude='*.test.ts' | tr -d '`' >> "$work/wanted"
sort -u -o "$work/wanted" "$work/wanted"
# Asked once the server has registered its groups, which it logs a moment after it starts; it exits once its input
# closes, and the alarm bounds it if it doesn't.
{
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"xcrew-canary","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  sleep 5
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  sleep 3
} | perl -e 'alarm 30; exec @ARGV' libexec/mobilebuildmcp-server "$project" > "$work/replies" 2> "$work/log" || true
# Each reply is one JSON line: the tool list is the one whose id is 2, read by its keys, not by its text.
: > "$work/listed"
while IFS= read -r reply; do
  printf '%s' "$reply" > "$work/reply.json"
  [ "$(plutil -extract id raw -o - "$work/reply.json" 2> /dev/null)" = 2 ] || continue
  count=$(plutil -extract result.tools raw -o - "$work/reply.json" 2> /dev/null || echo 0)
  index=0
  while [ "$index" -lt "$count" ]; do
    plutil -extract "result.tools.$index.name" raw -o - "$work/reply.json" >> "$work/listed"
    echo >> "$work/listed"
    index=$((index + 1))
  done
done < "$work/replies"
sort -u -o "$work/listed" "$work/listed"
if ! grep -q . "$work/listed"; then
  echo "registered-tools.sh: MobileBuildMCP listed no tools; its log:" >&2
  cat "$work/log" >&2
  exit 1
fi
missing=$(comm -23 "$work/wanted" "$work/listed")
if [ -n "$missing" ]; then
  echo "registered-tools.sh: MobileBuildMCP doesn't register: $(echo "$missing" | tr '\n' ' ')" >&2
  grep -E 'Registered [0-9]+ tools' "$work/log" >&2 || true
  exit 1
fi
if grep -E '^xcode_ide_|^xcode_tools_' "$work/listed" >&2; then
  echo "registered-tools.sh: MobileBuildMCP registers the xcode-ide bridge's tools" >&2
  exit 1
fi
