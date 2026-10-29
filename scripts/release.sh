#!/bin/sh
# Releases Xcrew: bumps the version, merges the release pull request, tags it and waits for the
# release workflow. Run from anywhere in a clone: scripts/release.sh 0.7.0
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

if ! git show origin/main:CHANGELOG.md | grep -q '^## Unreleased$'; then
  echo "release: CHANGELOG.md on main has no '## Unreleased' entry to release" >&2
  exit 1
fi
if git ls-remote --exit-code --tags origin "v$version" >/dev/null 2>&1; then
  echo "release: v$version is already tagged" >&2
  exit 1
fi

work=$(mktemp -d)
paused=""
finish() {
  for pr in $paused; do gh pr merge "$pr" --auto --squash >/dev/null 2>&1 || echo "release: turn auto-merge back on for #$pr" >&2; done
  git -C "$repo" worktree remove --force "$work/tree" 2>/dev/null || true
  git -C "$repo" branch -q -D "$branch" 2>/dev/null || true
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
git tag "v$version" origin/main
git push -q origin "v$version"

run=""
while [ -z "$run" ]; do
  sleep 5
  run=$(gh run list --workflow release.yml --branch "v$version" --limit 1 --json databaseId -q '.[0].databaseId')
done
gh run watch "$run" --exit-status >/dev/null
gh release view "v$version" --json url -q .url
