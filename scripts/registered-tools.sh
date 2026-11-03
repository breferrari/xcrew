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
# Asked once the server has answered `initialize` and logged its registered tools, and its input closed once it has
# answered `tools/list`: each step waits on what the server wrote, never on a time, and ends if the server exits.
mkfifo "$work/in"
libexec/mobilebuildmcp-server "$project" < "$work/in" > "$work/replies" 2> "$work/log" &
server=$!
exec 3> "$work/in"
until_written() {
  until grep -qE "$1" "$2" 2> /dev/null; do
    kill -0 "$server" 2> /dev/null || return 0
    sleep 0.1
  done
}
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"xcrew-canary","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' >&3
until_written '"id":1[,}]' "$work/replies"
until_written 'Registered [0-9]+ tools' "$work/log"
printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' >&3
until_written '"id":2[,}]' "$work/replies"
# It has answered all that's asked, and it may not exit on its input closing: it's stopped.
exec 3>&-
kill "$server" 2> /dev/null || true
wait "$server" 2> /dev/null || true
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
