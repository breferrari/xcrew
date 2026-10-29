#!/bin/sh
# Releases Xcrew: bumps the version, merges the release pull request, tags it, waits for the release
# workflow, then merges a second pull request that points the marketplace at the new tag. Run from
# anywhere in a clone: scripts/release.sh 0.7.0. Run it again after a failure: it finds the tag and goes on.
#
# It works in a throwaway worktree, so the clone you run it from is never touched. While it runs it
# turns off auto-merge on every other open pull request and turns it back on at the end: a feature
# merging between the bump and the tag ships under a version whose changelog doesn't list it.
# XCREW_BRANCH_PREFIX prefixes the release branch's name (for example `yourname/`).
set -eu

version=${1:-}
case $version in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "usage: scripts/release.sh <version>, e.g. 0.7.0" >&2; exit 64 ;;
esac
branch="${XCREW_BRANCH_PREFIX:-}release-$version"
repo=$(git rev-parse --show-toplevel)
cd "$repo"
git fetch -q origin

# A rerun picks up where the last run stopped: after the tag, at the release workflow; after the
# merge, at the tag. So every step can run again safely.
tagged=""
merged=""
if git ls-remote --exit-code --tags origin "v$version" >/dev/null 2>&1; then
  git fetch -q origin "refs/tags/v$version:refs/tags/v$version"
  if ! git merge-base --is-ancestor "v$version" origin/main || ! git show "v$version:.claude-plugin/plugin.json" | grep -q "\"version\": \"$version\""; then
    echo "release: v$version exists but isn't $version's release commit on main" >&2
    exit 1
  fi
  tagged=yes
  echo "release: v$version is tagged; going on from the release workflow"
elif git show origin/main:.claude-plugin/plugin.json | grep -q "\"version\": \"$version\""; then
  merged=yes
  echo "release: $version is merged but not tagged; going on from the tag"
elif ! git show origin/main:CHANGELOG.md | grep -q '^## Unreleased$'; then
  echo "release: CHANGELOG.md on main has no '## Unreleased' entry to release" >&2
  exit 1
fi
ref_branch="${XCREW_BRANCH_PREFIX:-}install-$version"

work=$(mktemp -d)
paused=""
finish() {
  for pr in $paused; do gh pr merge "$pr" --auto --squash >/dev/null 2>&1 || echo "release: turn auto-merge back on for #$pr" >&2; done
  git -C "$repo" worktree remove --force "$work/tree" 2>/dev/null || true
  git -C "$repo" worktree remove --force "$work/ref" 2>/dev/null || true
  git -C "$repo" branch -q -D "$branch" 2>/dev/null || true
  git -C "$repo" branch -q -D "$ref_branch" 2>/dev/null || true
  rm -rf "$work"
}
trap finish EXIT
# An interrupt stops the release: the cleanup runs once, on the way out, rather than the script carrying on after it.
trap 'exit 130' INT TERM

paused=$(gh pr list --state open --json number,autoMergeRequest -q '.[] | select(.autoMergeRequest != null) | .number')
for pr in $paused; do gh pr merge "$pr" --disable-auto >/dev/null; done
[ -n "$paused" ] && echo "release: auto-merge paused on $(echo "$paused" | tr '\n' ' ')"

# Merges a pull request once it's green, bringing it up to date whenever main moves ahead of it.
settle() {
  while :; do
    state=$(gh pr view "$1" --json state,mergeStateStatus -q '.state + " " + .mergeStateStatus')
    case $state in
      MERGED*) return 0 ;;
      CLOSED*) echo "release: #$1 was closed" >&2; return 1 ;;
      *DIRTY) echo "release: #$1 conflicts with main" >&2; return 1 ;;
      *BEHIND) gh pr update-branch "$1" >/dev/null 2>&1 || true ;;
    esac
    if gh pr checks "$1" 2>/dev/null | grep -q fail; then echo "release: #$1 failed CI" >&2; return 1; fi
    sleep 10
  done
}

if [ -z "$tagged" ] && [ -z "$merged" ]; then
  git worktree add -q -b "$branch" "$work/tree" origin/main
  cd "$work/tree"
  perl -pi -e "s/\"version\": \"[^\"]+\"/\"version\": \"$version\"/" .claude-plugin/plugin.json
  perl -pi -e "s/current = \"[^\"]+\"/current = \"$version\"/" Sources/XcrewCore/XcrewVersion.swift
  perl -pi -e "s/^## Unreleased\$/## $version — $(date +%Y-%m-%d)/" CHANGELOG.md
  swift test --filter ManifestTests >/dev/null
  git commit -qam "Release $version"
  git push -q -u origin "$branch"

  # shellcheck disable=SC2016 # the backticks are markdown, not a command
  printf '## Summary\n\nBump to %s and date the changelog.\n\n## Test plan\n\n`ManifestTests` pass.\n\n## Release note\n\nnone\n' "$version" >"$work/body.md"
  pr=$(gh pr create --base main --head "$branch" --title "chore: release $version" --body-file "$work/body.md" | sed 's|.*/||')
  gh pr merge "$pr" --auto --squash >/dev/null
  settle "$pr"

  git fetch -q origin
  if ! git show origin/main:.claude-plugin/plugin.json | grep -q "\"version\": \"$version\""; then
    echo "release: main doesn't declare $version after the merge" >&2
    exit 1
  fi
fi
if [ -z "$tagged" ]; then
  # The release commit is the one that set the version, wherever main has moved since.
  commit=$(git log -1 --format=%H -G"\"version\": \"$version\"" origin/main -- .claude-plugin/plugin.json)
  git tag -f "v$version" "$commit" >/dev/null
  git push -q origin "v$version"
fi

run=""
while [ -z "$run" ]; do
  sleep 5
  run=$(gh run list --workflow release.yml --branch "v$version" --limit 1 --json databaseId -q '.[0].databaseId')
done
installed=$(git show origin/main:.claude-plugin/marketplace.json | sed -n 's/.*"ref": "\(v[^"]*\)".*/\1/p')
if [ -z "$installed" ]; then
  echo "release: .claude-plugin/marketplace.json on main has no \"ref\": \"v…\" line to move" >&2
  exit 1
fi
if ! gh run watch "$run" --exit-status >/dev/null; then
  echo "release: the release workflow refused v$version, so the marketplace still installs $installed." >&2
  echo "release: read why with: gh run view $run --log-failed" >&2
  echo "release: if a rerun can pass, run: gh run rerun $run, then scripts/release.sh $version" >&2
  echo "release: if the tagged commit itself is wrong, leave v$version as it is, fix main, and release the next version" >&2
  exit 1
fi

# The marketplace moves to the new tag only now that it exists and the workflow published it.
if [ "$installed" != "v$version" ]; then
  pr=$(gh pr list --head "$ref_branch" --state open --json number -q '.[0].number')
  if [ -z "$pr" ]; then
    cd "$repo"
    git fetch -q origin
    git worktree add -q -B "$ref_branch" "$work/ref" origin/main
    cd "$work/ref"
    perl -pi -e "s/\"ref\": \"v[^\"]+\"/\"ref\": \"v$version\"/" .claude-plugin/marketplace.json
    git commit -qam "Install $version from the marketplace"
    git push -q -f -u origin "$ref_branch"
    printf '## Summary\n\nPoint the marketplace at v%s, now that the release workflow has published it.\n\n## Test plan\n\nCI passes.\n\n## Release note\n\nnone\n' "$version" >"$work/ref.md"
    pr=$(gh pr create --base main --head "$ref_branch" --title "chore: Install $version from the marketplace" --body-file "$work/ref.md" | sed 's|.*/||')
  fi
  gh pr merge "$pr" --auto --squash >/dev/null
  settle "$pr"
fi
gh release view "v$version" --json url -q .url
