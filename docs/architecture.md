# Architecture

## One implementation, three entry points

All behaviour lives in a dependency-free Swift package. Everything else is a thin entry point that calls its CLI:

| Entry point | Calls |
| --- | --- |
| Plugin hooks (`hooks/hooks.json`) | `bin/xcrew hook session-start`, `bin/xcrew hook repair-macros` |
| Mod (`hooks/mod/`) | `bin/xcrew repair-macros` and `bin/xcrew doctor`, through `$.process.run` |
| Skills (`skills/`) | `xcrew setup`, `xcrew doctor`, which the plugin puts on Claude's `PATH` |
| mcs (`techpack.yaml`) | `mcs/configure.sh` → `xcrew setup`; `mcs/checks/*.sh` → `xcrew doctor --check <id>` |

`bin/xcrew` builds the package on first use, keyed by a hash of its sources, so a plugin update rebuilds once and removes the build it replaces, and Swift's ABI stability keeps a build working across Xcode updates.

## Why a CLI

The mod alone could hold most of this logic, in TypeScript. The CLI exists because every other way in needs an executable:

- **mcs** runs a configure script and one script per doctor check; it never loads the mod.
- **The plugin's command hooks** are the fallback where mods don't run, such as an organization that allows only its own mods.
- **Claude** runs `xcrew doctor` and `xcrew setup` from the skills.

One CLI keeps one implementation of each behaviour, tested with Swift Testing in the language the people who'll change it write. The mod stays thin: it decides when to act and calls the CLI to act.

## The Swift package

```
Sources/
  XcrewCore/            the behaviour, no I/O beyond what Machine allows
    System/             CommandRunning (the seam every process call goes through), Machine, Version
    Project/            the project root, the files xcrew reads or writes there, git exclusion
    MobileBuildMCP/     profile answers, config rendering and writing, the simulator catalog
    MacroPlugins/       locating, probing and repairing macro plugins
    Doctor/             the Check protocol, the registry, and one file per check in Checks/
    Hooks/              hook input and replies, the session briefing
    XcodeSkills/        finding and copying the skills Xcode ships
    XcrewVersion.swift  the version, held equal to plugin.json and the changelog
  XcrewCLI/             one Command type per subcommand, and the dispatcher
  xcrew/                main.swift: builds the live Machine and calls CLI.run
Tests/
  XcrewCoreTests/       behaviour, through FakeRunner; macro plugins with real compiled stubs
  XcrewCLITests/        commands, in-process, with output captured
  ShimTests/            bin/xcrew against a fake swift
  ManifestTests/        the plugin, the mod and the techpack agree with the Swift code
  XcrewTestSupport/     FakeRunner and temporary projects, shared by the suites
```

Everything that touches the machine goes through `Machine` (environment, home folder, `CommandRunning`). Production passes `Machine.live`; tests pass a `FakeRunner` and a temporary home, so no test depends on how the Mac running it is set up.

## The mod

`hooks/mod/register.ts` registers three `tool.call` hooks. Hooks on one event run in registration order, each wrapping the next:

1. **guard**: matched on `XcodeWrite`; refuses it when the project root has a Tuist or XcodeGen manifest, and lets it through in a classic project. A `tool.describe` hook on the same tool adds that to its description, so Claude reaches for Write first.
2. **timing**: the one unmatched hook; times calls `tools.ts` classifies as build, test or run, by name pattern so new tools are timed without a change. It keeps the last ten durations per tool in `$.store`, compares each run with them, and calls out one far slower than usual. Its bookkeeping is best-effort and never fails a build.
3. **repair**: matched on the Xcode tools that build; on "produced malformed response" it runs `xcrew repair-macros`, calls `next` again, and toasts what it repaired and, when the CLI names one, the cause.

Beside those, **band** (`ui.render` on `AbovePrompt`) draws the run that timing records in `$.state`, its gauge and phase (**progress** reads MobileBuildMCP's log), or, before the first run, the problem **problems** found with `xcrew doctor --problems`. **session** is the one unmatched `session.start` hook: it registers `/xcrew` and starts that look for problems without holding the session up. **command** answers `/xcrew` itself: `doctor` and `repair` run the CLI, `history` reads timing's durations, kept per tool, scheme and test selection, and `failures` opens the **failures** pane, which keeps the last failing run's failures.

Every tool name is matched under both registrations: `mcp__plugin_xcrew_<server>__<tool>` from this plugin, and `mcp__<server>__<tool>` when the person registered the server themselves, which Claude Code then prefers.

## Extending

| To add | Write | Then |
| --- | --- | --- |
| A health check | A `Check` in `Sources/XcrewCore/Doctor/Checks/`, listed in `Doctor.checks` | A wrapper in `mcs/checks/` and an entry in `techpack.yaml`; `ManifestTests` fails until both exist |
| A CLI command | A `Command` in `Sources/XcrewCLI/`, listed in `CLI.commands` | Tests in `XcrewCLITests` |
| A setup question | An option in `SetupCommand.mcsKeys` | A prompt in `techpack.yaml`; `ManifestTests` fails until it exists |
| A mod behaviour | A `register…` function in `hooks/mod/`, called from `register.ts` | Tests in `hooks/mod/`, calling tools through `testing.ts`; at most one unmatched hook per event; `scripts/typecheck.sh` clean |
| A repairable Xcode tool | Its name in `REPAIRABLE_XCODE_TOOLS` | The same name in the `PostToolUseFailure` matcher; `ManifestTests` fails until it's there |
