#!/bin/sh
# Fails when the stable branch, which installs follow, isn't the latest release: behind it a day after it was published,
# or holding commits no release has.
# scripts/stable-check.sh <latest tag> <published, ISO 8601 UTC> <now, epoch seconds> <GitHub's compare status of tag...stable>
set -eu
latest=$1 published=$2 now=$3 status=$4
case $status in
  identical) exit 0 ;;
  behind)
    released=$(date -u -j -f %Y-%m-%dT%H:%M:%SZ "$published" +%s)
    [ $((now - released)) -le 86400 ] && exit 0
    echo "installs follow stable, which is behind $latest, released at $published: rerun $latest's release workflow, which moves stable" >&2 ;;
  ahead | diverged)
    echo "stable is $status of $latest: installs run code no release has. Release it, or have the repository's owner reset stable to $latest, since its ruleset refuses a rewind" >&2 ;;
  *)
    echo "couldn't compare stable with $latest (GitHub answered '$status')" >&2 ;;
esac
exit 1
