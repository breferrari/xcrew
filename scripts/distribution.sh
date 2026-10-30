#!/bin/sh
# Fails when a channel xcrew ships through would no longer install: what each channel's manifest promises, checked as
# that channel's installer or listing reads it. One step per channel; a new channel is one more case here and one more
# step in ci.yml. Each runs its channel's ManifestTests by their name's prefix.
# scripts/distribution.sh <channel>...   channels: marketplace, listing, techpack
set -eu
cd "$(dirname "$0")/.."
[ $# -gt 0 ] || { echo "usage: scripts/distribution.sh <channel>..." >&2; exit 64; }
for channel in "$@"; do
  case $channel in
  marketplace)
    # The Claude marketplace: marketplace.json and plugin.json, as Claude Code loads them.
    claude plugin validate .
    ;;
  listing)
    # The plugin directory's listing: plugin.json's listing fields and the README it shows.
    ;;
  techpack)
    # The techpack manifest. Its installer's lint joins here once it answers in JSON.
    ;;
  *)
    echo "distribution.sh: no channel named $channel" >&2
    exit 64
    ;;
  esac
  swift test --filter "ManifestTests\.ManifestTests/$channel"
done
