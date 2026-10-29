#!/bin/sh
# Fails when installs, which follow the stable branch, are still behind the latest release a day after it was published.
# scripts/marketplace-ref.sh <latest tag> <published, ISO 8601 UTC> <now, epoch seconds> <stable's commit> <the tag's commit>
set -eu
latest=$1 published=$2 now=$3 stable=$4 tagged=$5
[ "$stable" = "$tagged" ] && exit 0
released=$(date -u -j -f %Y-%m-%dT%H:%M:%SZ "$published" +%s)
[ $((now - released)) -le 86400 ] && exit 0
short() { printf '%.12s' "$1"; }
echo "installs follow stable at $(short "$stable"), but $latest ($(short "$tagged")) was released at $published: rerun its release workflow, or push it with git push origin $tagged:refs/heads/stable" >&2
exit 1
