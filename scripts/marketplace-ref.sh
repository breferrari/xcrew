#!/bin/sh
# Fails when the marketplace still installs an older release a day after the latest was published.
# scripts/marketplace-ref.sh <latest tag> <published, ISO 8601 UTC> <now, epoch seconds>
set -eu
cd "$(dirname "$0")/.."
latest=$1 published=$2 now=$3
ref=$(sed -n 's/.*"ref": *"\(v[^"]*\)".*/\1/p' .claude-plugin/marketplace.json)
[ "$ref" = "$latest" ] && exit 0
released=$(date -u -j -f %Y-%m-%dT%H:%M:%SZ "$published" +%s)
[ $((now - released)) -le 86400 ] && exit 0
version=${latest#v}
echo "marketplace.json installs $ref, but $latest was released at $published: merge its 'chore: Install $version from the marketplace' pull request, or run scripts/release.sh $version to open it" >&2
exit 1
