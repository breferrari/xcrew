#!/bin/sh
# Fails when an image the README shows no longer loads: they live in xcrew-assets at the commit the README pins, and
# the plugin directory's listing shows the README with them, so a missing one shows as alt text there.
# scripts/readme-images.sh
set -eu
cd "$(dirname "$0")/.."
urls=$(grep -oE 'https://raw\.githubusercontent\.com/breferrari/xcrew-assets/[0-9a-f]+/[^"]+' README.md | sort -u)
[ -n "$urls" ] || { echo "readme-images.sh: the README names no xcrew-assets image" >&2; exit 1; }
failed=0
for url in $urls; do
  # 3 × the slowest of 30 fetches, 0.75 s (measured 2026-11-02 off CI), up to the next 10 seconds.
  type=$(curl --fail --silent --show-error --max-time 10 --output /dev/null --write-out '%{content_type}' "$url") || { echo "readme-images.sh: $url doesn't load" >&2; failed=1; continue; }
  case $type in
    image/*) ;;
    *) echo "readme-images.sh: $url answers $type, not an image" >&2; failed=1 ;;
  esac
done
exit $failed
