#!/bin/sh
# Fails when the installed Claude Code stops updating a plugin that follows a branch by its version, which installs from
# the stable branch rely on (docs/findings.md, *Installs that follow a branch*). Everything is local: a throwaway
# config, a marketplace folder, and a plugin served from a bare repository.
# scripts/stable-follows.sh
set -eu
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export CLAUDE_CONFIG_DIR="$root/config"
mkdir -p "$root/work/.claude-plugin" "$root/work/skills/hello" "$root/market/.claude-plugin" "$CLAUDE_CONFIG_DIR"
cd "$root/work"
git init -q -b stable
version() { printf '{"name":"probe","version":"%s","description":"probe"}\n' "$1" > .claude-plugin/plugin.json; }
commit() { git add -A && git -c user.name=probe -c user.email=probe@example.com commit -qm "$1"; }
version 1.0.0
printf -- '---\nname: hello\ndescription: Says hello.\n---\nSay hello.\n' > skills/hello/SKILL.md
commit 1.0.0
git clone -q --bare "$root/work" "$root/plugin.git"
git remote add origin "$root/plugin.git"
printf '{"name":"probe-market","owner":{"name":"probe"},"plugins":[{"name":"probe","source":{"source":"url","url":"file://%s/plugin.git","ref":"stable"}}]}\n' "$root" > "$root/market/.claude-plugin/marketplace.json"
installed() { sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json" | head -1; }
fail() { echo "a plugin following a branch: $1" >&2; exit 1; }

claude plugin marketplace add "$root/market" < /dev/null > /dev/null
claude plugin install probe@probe-market < /dev/null > /dev/null
[ "$(installed)" = 1.0.0 ] || fail "installed $(installed), not 1.0.0, from the branch"
version 1.0.1
commit 1.0.1
git push -q origin stable
claude plugin update probe@probe-market < /dev/null > /dev/null
[ "$(installed)" = 1.0.1 ] || fail "stayed on $(installed) after the branch moved to 1.0.1: installs no longer follow stable to a release"
echo more >> skills/hello/SKILL.md
commit "same version"
git push -q origin stable
claude plugin update probe@probe-market < /dev/null > /dev/null
[ "$(installed)" = 1.0.1 ] || fail "moved to $(installed) though the version didn't change: installs would take stable's commits between releases"
