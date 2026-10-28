# Contributing

Thanks for helping. Xcrew is small on purpose: one Swift package does the work, and every other file is a thin way to reach it.

## The short version

- **A plain report is welcome.** Two lines is enough: what you expected, what happened. `xcrew doctor`'s output helps, and isn't required.
- **Reports from use are the scarcest thing this project has.** A report that starts *"I was building with Claude and…"* is worth more than a well-formed proposal.
- **Discussions are open** for anything that isn't yet a bug or a proposal.

## Set up

macOS 26 or later with Xcode 27 or later, and Claude Code.

```sh
git clone https://github.com/breferrari/xcrew && cd xcrew
swift test
claude plugin test .
claude --plugin-dir .   # try your checkout in a real session
scripts/typecheck.sh    # the mod's types; needs that session once
```

## How changes are made

- **Test first.** Write the test for the behaviour you're adding, watch it fail for the reason you expect, then write the code that passes it. Pull requests say which tests were seen failing first.
- **Keep install paths in step.** The plugin and the mcs techpack name the same hooks, checks and setup questions as the Swift code; `Tests/ManifestTests` fails when they drift, so a red parity test usually means a second file to update.
- **Prefer discovering to hard-coding.** If a value can change with a new Xcode, simulator lineup or server release, read it at runtime.
- **No dependencies, no unsafe code.** See [CLAUDE.md](CLAUDE.md) for the full conventions; they apply to people as much as to Claude.

## House rules

- **Titles say what to fix or what to build.** One imperative clause, no "because"; the explanation goes in the body. Start a pull request title with its kind: `fix:` for a defect or `feat:` for a new feature that users get, otherwise `ci:`, `docs:`, `test:` or `chore:`. Issue titles are imperative too, without the prefix.
- **A pull request carries its release note.** The template's last section is one line for someone who has never opened this repository, saying what changed for them, or `none` for internal work. The same line goes under `## Unreleased` in `CHANGELOG.md`.
- **Numbers or it didn't happen.** A test plan says what ran and how it went, with counts and timings; a single green run of something flaky isn't evidence.
- **Don't hard-wrap prose.** One paragraph is one line in markdown, PR bodies and commit bodies, because GitHub renders a single newline as a line break.

[docs/architecture.md](docs/architecture.md) shows where things live and how to add a check, a command, a setup question or a mod behaviour.

## Releasing

Claude Code keeps people on a plugin's `version` until it changes, so every release bumps it:

1. Set the new version in `Sources/XcrewCore/XcrewVersion.swift` and `.claude-plugin/plugin.json`, and turn the changelog's top entry into `## <version> — <date>`. `ManifestTests` fails until all three agree.
2. Merge to `main` with CI green, then tag it: `git tag v<version> && git push --tags`. The release workflow refuses a tag that doesn't match the declared version, then publishes the release with its changelog entry.

Between releases, `main` moves ahead of the version people have installed; that's expected, and it's why a release is a version bump.

## Reporting a problem

Open an issue; the form asks for what you expected and what happened, and optionally for `/xcrew doctor`'s output and your versions. Security issues go through [SECURITY.md](SECURITY.md) instead.

## Licence

By contributing you agree that your contribution is licensed under the same terms as the project.
