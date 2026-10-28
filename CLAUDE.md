# Xcrew

A Claude Code plugin (with a mod) and an mcs techpack that set up Apple's Xcode MCP, MobileBuildMCP and Sosumi for iOS projects. All behaviour is one dependency-free Swift package; the plugin hooks, the mod, the skills and mcs call its CLI through `bin/xcrew`. Layout and extension points: [docs/architecture.md](docs/architecture.md). Evidence behind the choices: [docs/findings.md](docs/findings.md).

## Commands

```sh
swift test                              # all Swift suites
swift test -Xswiftc -warnings-as-errors # what CI runs
claude plugin test .                    # the mod's tests
scripts/typecheck.sh                    # the mod's types, after one `claude --plugin-dir .`; not in CI
claude plugin validate .
mcs pack validate .
```

## It must keep working untouched for a year

- **Discover, don't hard-code** anything that ages: simulator names come from `simctl`, Xcode's skills from the installed Xcode, build and test tools from name patterns in `hooks/mod/tools.ts`. A fixed list is acceptable only where a pattern can't express it, and then a test pins it.
- **One source of truth per fact.** Where two files must name the same thing (the plugin's hooks and the mod, the techpack and the Swift checks or setup options), `Tests/ManifestTests` asserts they agree. Extend it with every new pairing.
- **Every failure mode the doctor can see gets a check** whose message names the fix.
- **Docs carry no counts or versions that drift**, except dated evidence in `docs/findings.md`.
- **Warnings become errors only in CI**, never in `Package.swift`: a newer Swift adding a warning must not break a user's first build.

## Swift

- Swift 6.2 tools, macOS 26 (Xcode 27 requires it), Swift 6 language mode, and the `swiftSettings` in `Package.swift` on every target: upcoming features enabled, strict memory safety. No `unsafe` code; find a safe API instead.
- No package dependencies: `bin/xcrew` builds the package on users' Macs, offline included.
- async/await throughout; concurrency is proven by the compiler (`Sendable`, `Mutex`), never asserted with `@unchecked` or `nonisolated(unsafe)`.
- Everything that touches the machine goes through `Machine` and `CommandRunning`, so tests run with `FakeRunner` and a temporary home.
- One type per file, grouped by feature. New checks go in `Doctor.checks`, new commands in `CLI.commands`.
- No comment by default. Doc comments (`///`) on types and members say what they are for and any constraint the code can't show.

## The mod

- At most one hook per event without a matcher (the engine refuses a second); give the others a matcher.
- Match every tool under both registrations, `mcp__plugin_xcrew_<server>__<tool>` and `mcp__<server>__<tool>`, with a regular expression from `tools.ts`: a list of names only type-checks for the MCP servers connected on the machine that laid the types.
- Tests call tools and commands through `hooks/mod/testing.ts` for the same reason.
- Bookkeeping (clock, store, UI) is best-effort and never fails the tool call it wraps.

## Tests

- New behaviour is test-first: one failing test, seen failing for the right reason, then the code that passes it. Report the count of tests seen red then green; a test that never failed is reported as such.
- Seams: core behaviour through `XcrewCore` with `FakeRunner`; commands in-process through `CLI.run`; the shim by running it against a fake `swift`; the mod with `claude plugin test`; consistency through `ManifestTests`. Macro-plugin tests compile real stub binaries.
- Expected values come from a literal or the spec, never recomputed the way the code computes them.

## Working on macOS

- The filesystem is case-insensitive: `tests/` and `Tests/` are one folder.
- zsh's `noclobber` refuses `>` over an existing file; use `>|` or run the snippet in `bash`.
- BSD `sed` has no `\b`; use `perl -pi -e`.

## This repository is public

No company names, internal project names, personal names or private paths in code, tests, docs or commits; describe a setup generically ("a large modular Tuist app").
