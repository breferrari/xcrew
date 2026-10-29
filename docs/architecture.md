# Architecture

## One implementation, three entry points

All behaviour lives in a dependency-free Swift package. Everything else is a thin entry point that calls its CLI:

| Entry point | Calls |
| --- | --- |
| Plugin hooks (`hooks/hooks.json`) | `bin/xcrew hook session-start` |
| Mod (`hooks/mod/`) | `report`, `phase`, `project` and `doctor`, through `cli.ts`, on the build `bin/xcrew --binary-path` names |
| Skills (`skills/`) | `xcrew setup`, `xcrew doctor`, which the plugin puts on Claude's `PATH` |
| mcs (`techpack.yaml`) | `mcs/configure.sh` → `xcrew setup`; `mcs/checks/*.sh` → `xcrew doctor --check <id>` |

`bin/xcrew` builds the package on first use, keyed by a hash of its sources, so a plugin update rebuilds once, and Swift's ABI stability keeps a build working across Xcode updates. It keeps that key in its cache and hashes again only when a source changes. One build runs at a time, and a build no checkout has run for two weeks is removed, so the installed plugin and a development clone each keep theirs.

## Why a CLI

The mod alone could hold most of this logic, in TypeScript. The CLI exists because every other way in needs an executable:

- **mcs** runs a configure script and one script per doctor check; it never loads the mod.
- **The plugin's session-start hook** briefs Claude on routing and on what the project still lacks, including where mods don't run, such as an organization that allows only its own mods.
- **Claude** runs `xcrew doctor` and `xcrew setup` from the skills.

One CLI keeps one implementation of each behaviour, tested with Swift Testing in the language the people who'll change it write. The mod stays thin: it decides when to act and calls the CLI to act.

## The Swift package

```
Sources/
  XcrewCore/            the behaviour, no I/O beyond what Machine allows
    System/             CommandRunning (the seam every process call goes through), Machine, Version, Once
    Project/            the project root, the files xcrew reads or writes there, git exclusion, Tuist's old macro copy phase
    MobileBuildMCP/     profile answers, config rendering and writing, the simulator catalog
    Doctor/             the Check protocol, the registry, and one file per check in Checks/
    Hooks/              hook input and replies, the session briefing
    Reports/            reading the servers' output for the mod: each result decoded once into its server's shape (MobileBuildMCP's text as typed lines, every line shape read in MobileBuildMCPLine), failures, logs, result bundles
    XcodeSkills/        finding and copying the skills Xcode ships
    XcrewVersion.swift  the version, held equal to plugin.json and the changelog
  XcrewCLI/             one Command type per subcommand, and the dispatcher
  xcrew/                main.swift: builds the live Machine and calls CLI.run
Tests/
  XcrewCoreTests/       behaviour, through FakeRunner
  XcrewCLITests/        commands, in-process, with output captured
  ShimTests/            bin/xcrew against a fake swift
  ManifestTests/        the plugin, the mod and the techpack agree with the Swift code
  XcrewTestSupport/     FakeRunner and temporary projects, shared by the suites
```

Everything that touches the machine goes through `Machine` (environment, home folder, `CommandRunning`). Production passes `Machine.live`; tests pass a `FakeRunner` and a temporary home, so no test depends on how the Mac running it is set up.

## The mod

`hooks/mod/register.ts` registers two `tool.call` hooks. Hooks on one event run in registration order, each wrapping the next:

1. **guard**: matched on `XcodeWrite`; refuses it when `xcrew project` says Tuist or XcodeGen generates the project (manifests at the root or up to two folders below it), and lets it through in a classic project or when the CLI can't say. A `tool.describe` hook on the same tool adds that to its description, so Claude reaches for Write first.
2. **timing**: the one unmatched hook; times calls `tools.ts` classifies as build, test or run, by name pattern so new tools are timed without a change. It keeps the last ten durations per tool in `$.store`, compares each run with them, and calls out one far slower than usual. Its bookkeeping is best-effort and never fails a build.

`cli.ts` runs the build the shim names directly, asking the shim again every 30 s, so the once-a-second poll skips the shim's work; when that build can't be started, the shim runs the command instead. Timing reads nothing itself. While a MobileBuildMCP run goes it asks `xcrew phase` once a second for the run's log and phase; when the call ends it pipes the result to `xcrew report`, which returns the outcome, the failures, the duration, and the shorter result and notes Claude reads.

Beside those, **band** (`ui.render` on `AbovePrompt`) draws the run that timing records in `$.state`, its gauge and phase, or, before the first run, the problem **problems** found with `xcrew doctor --problems --json`. **session** is the one unmatched `session.start` hook: it registers `/xcrew` and starts that look for problems without holding the session up. **command** answers `/xcrew` itself: `doctor` runs the CLI, `history` reads timing's durations, kept per tool, scheme and test selection, `failures` opens the **failures** pane, which keeps the last failing run's failures, and `close` closes it. The pane opens only when asked, since docked or above the prompt it takes room from the chat; after a failing run the band ends with `/xcrew failures`.

Every tool name is matched under both registrations: `mcp__plugin_xcrew_<server>__<tool>` from this plugin, and `mcp__<server>__<tool>` when the person registered the server themselves, which Claude Code then prefers.

### The mod's boundary

The mod does what only TypeScript can reach, and hands everything else to the CLI:

| The mod does | The CLI does |
| --- | --- |
| Register hooks, and decide which calls to act on, by tool name | Read and parse what the servers print as text: results, logs |
| Draw the band and the pane, keep `$.state` and `$.store` | Read files, run `xcrun` and other programs |
| Time calls, and hand a result back to Claude | Decide what a result means and what Claude reads instead |

Reading a few named fields of a JSON answer is fine: **context** learns the scheme and simulator that way. So in `hooks/mod/`, only `cli.ts` runs a process, from one place, and only the CLI: the build `bin/xcrew --binary-path` names, or the shim, only `cli.ts` and `context.ts` parse JSON, only `tools.ts` matches a pattern, and nothing touches the file system. `ModBoundaryTests` in `Tests/ManifestTests` fails on any of these anywhere else. When a change seems to need one, the logic belongs in a Swift command the mod calls through `cli.ts`, tested with Swift Testing against captured output in `Tests/XcrewCoreTests/Fixtures`.

## Extending

| To add | Write | Then |
| --- | --- | --- |
| A health check | A `Check` in `Sources/XcrewCore/Doctor/Checks/`, listed in `Doctor.checks` | A wrapper in `mcs/checks/` and an entry in `techpack.yaml`; `ManifestTests` fails until both exist |
| A CLI command | A `Command` in `Sources/XcrewCLI/`, listed in `CLI.commands` | Tests in `XcrewCLITests` |
| A setup question | An option in `SetupCommand.mcsKeys` | A prompt in `techpack.yaml`; `ManifestTests` fails until it exists |
| A mod behaviour | A `register…` function in `hooks/mod/`, called from `register.ts`; anything it needs read or worked out, in a Swift command it calls through `cli.ts` (see *The mod's boundary*) | Tests in `hooks/mod/`, calling tools through `testing.ts` and answering for the CLI with `stubCli`; at most one unmatched hook per event; `scripts/typecheck.sh` clean |
