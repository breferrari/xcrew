#!/bin/sh
# Fails when the stable branch, which installs follow, isn't the latest release: behind it once that release's run has
# ended, or holding commits no release has. It reads state, never the clock: a release run still going is no failure.
# scripts/stable-check.sh <latest tag> <its release run's status, as GitHub gives it: completed, or another while it goes> <GitHub's compare status of tag...stable>
set -eu
latest=$1 run=$2 status=$3
case $status in
  identical) exit 0 ;;
  behind)
    case $run in
      completed) ;;
      "") echo "stable is behind $latest, and its release run's status couldn't be read: gh run list --workflow release.yml --branch $latest reads it" >&2; exit 1 ;;
      # Any other status is a run still going.
      *) exit 0 ;;
    esac
    echo "installs follow stable, which is behind $latest, though its release run has ended: rerun $latest's release workflow, which moves stable" >&2 ;;
  ahead | diverged)
    echo "stable is $status of $latest: installs run code no release has. Release it, or have the repository's owner reset stable to $latest, since its ruleset refuses a rewind" >&2 ;;
  *)
    echo "couldn't compare stable with $latest (GitHub answered '$status')" >&2 ;;
esac
exit 1
