# Architecture

## One implementation, three entry points

All behaviour lives in a dependency-free Swift package. Everything else is a thin entry point that calls its CLI:

| Entry point | Calls |
| --- | --- |
| Plugin hooks (`hooks/hooks.json`) | `bin/xcrew hook session-start` |
| Mod (`hooks/mod/`) | `report`, `phase`, `project` and `doctor`, through `cli.ts`, on the build `bin/xcrew --binary-path` names |
| Skills (`skills/`) | `xcrew setup`, `xcrew project --setup`, `xcrew doctor`, which the plugin puts on Claude's `PATH` |
| mcs (`techpack.yaml`) | `mcs/configure.sh` → `xcrew setup`; `mcs/checks/*.sh` → `xcrew doctor --check <id>` |

The two local MCP servers start from scripts in `libexec/`, `mobilebuildmcp-server` and `xcode-mcp-server`, rather than from an inline shell command: the plugin directory reads a server command only as a file of the plugin with plain arguments. `libexec/` stays off Claude's `PATH`, which `bin/` is on. They're declared in the manifest's `mcpServers`, not a root `.mcp.json`, because the plugin's root is this repository's, where Claude Code would read that file as the project's own. `mobilebuildmcp-server` also gives the server the project's pinned Xcode as `DEVELOPER_DIR`, asking `bin/xcrew --if-built xcode --developer-dir` only of a build already there and only briefly, and records what it did for the doctor.

`bin/xcrew` builds the package on first use, keyed by a hash of its sources, so a plugin update rebuilds once, and Swift's ABI stability keeps a build working across Xcode updates. It keeps that key in its cache and hashes again only when a source changes. One build runs at a time, and a build no checkout has run for two weeks is removed, so the installed plugin and a development clone each keep theirs.

## Why a CLI

The mod alone could hold most of this logic, in TypeScript. The CLI exists because every other way in needs an executable:

- **mcs** runs a configure script and one script per doctor check; it never loads the mod.
- **The plugin's session-start hook** briefs Claude on routing and on what the project still lacks, including where mods don't run, such as an organization that allows only its own mods. When MobileBuildMCP is missing or older than the minimum (the doctor's `mobilebuildmcp/version`, one assessment for both), the briefing sends builds and tests to the Xcode MCP's `BuildProject` and `RunAllTests` and says what that loses. A version that can't be read fails the doctor but doesn't fail over, since the server may still run.
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
    Reports/            reading the servers' output for the mod: each result decoded once into its server's shape (MobileBuildMCP's text as typed lines, every line shape read in MobileBuildMCPLine), failures, the warnings in lines the branch changed, the changed lines a test run ran, logs, result bundles
    XcodeSkills/        finding and copying the skills Xcode ships
    Xcode/              the installed Xcodes, the selected and open ones, the project's `.xcode-version` pin and CI's
    Affected/           which tests a change can break: the project file read for target ownership and dependencies
    Look/               a failed UI test's runs from its result bundle: the steps before each failure, the screen at it from the run's recording, and the accessibility hierarchy XCTest attached
    XcrewVersion.swift  the version, held equal to plugin.json and the changelog; the marketplace installs it from the `stable` branch
  XcrewCLI/             one Command type per subcommand, and the dispatcher
  xcrew/                main.swift: builds the live Machine and calls CLI.run
Tests/
  XcrewCoreTests/       behaviour, through FakeRunner
  XcrewCLITests/        commands, in-process, with output captured
  ShimTests/            bin/xcrew against a fake swift, and the libexec/ server scripts against fake servers
  ManifestTests/        the plugin, the mod and the techpack agree with the Swift code
  XcrewTestSupport/     FakeRunner and temporary projects, shared by the suites
```

Everything that touches the machine goes through `Machine` (environment, home folder, `CommandRunning`). Production passes `Machine.live`; tests pass a `FakeRunner` and a temporary home, so no test depends on how the Mac running it is set up.

## The mod

`hooks/mod/register.ts` is the hooks module: it registers every hook and makes every `$` call. Its `tool.call` hooks run in registration order, each wrapping the next:

1. **guard**: matched on `XcodeWrite`, also as MobileBuildMCP's `xcode-ide` bridge forwards it. `parseTool` in `tools.ts` reads a proxied `xcode_tools_<name>` as the Xcode tool itself, for every hook, and `forwardedTool` reads the tool `xcode_ide_call_tool` names, for the guard and the stale refusal. When `xcrew project` says Tuist or XcodeGen generates the project (manifests at the root or up to two folders below it), it holds the call and asks the person with `$.ui.ask`: yes runs it, and no, or nobody to ask, refuses it with the reason. It lets the call through in a classic project or when the CLI can't say. A `tool.describe` hook on the same tool adds that to its description, so Claude reaches for Write first.
2. **stale**: matched on either server's tools. After a manifest edit, the first build, test or run that builds (not a clean or a launch of what was built, by `buildsProject` in `tools.ts`) is refused with the command that regenerates the project, and the next goes through with a line saying so, since the person may have generated in their own terminal.
3. **setup**: matched on either server's tools, acting on MobileBuildMCP's builds and tests. With the session's first one, it marks the session in `$.state` before the call, so calls started together ask once, then asks `xcrew project --profiles`. While MobileBuildMCP has no scheme to build with (the active profile's, or with none active, the global defaults'), the CLI answers with the session briefing's own line offering `/xcrew:setup`, and the result carries it.
4. **manifests**: matched on Write and Edit. Before the call, a path inside a bundle or a `Derived` folder asks `xcrew project --generated <file>` whether a generator writes it; when one does, the call waits on the same question, naming the manifest to edit instead and the generate command. After the call, when the edited file's name is one a generator may read, it asks `xcrew project --manifest <file>`, which decides by the same rule detection uses, and for XcodeGen by the specs its spec includes and names the generate command. It then marks that app stale in `$.state`, one mark per app, and adds a line to the edit's result. A Bash call that runs a generate and succeeds clears the mark of each app it names, by its `--path` or `--spec` or a `cd` just before it, or every mark when it names none, since it may have run anywhere; that holds only when nothing after the generate but `&&` or a redirection could hide its exit status. An edit to `Tuist/Package.swift` names `tuist install` before the generate. Why file times can't do this is in docs/findings.md, *When a generated project is stale*.
5. **timing**: the one unmatched hook; times calls `tools.ts` classifies as build, test or run, by name pattern so new tools are timed without a change. It keeps the last ten durations per tool in `$.store`, dated, compares each run with them, and calls out one far slower than usual. Durations no run has updated for as long as the CLI keeps an unused build don't count, and `/xcrew history` deletes them. Its bookkeeping is best-effort and never fails a build. A build or test whose result holds nothing in its server's own forms (`isUnread` from `xcrew report`), as a call moved to the background answers with a handle, shows as neither passed nor failed and is recorded nowhere: no duration, no ledger entry, no card, no transcript row. When the background task's notification row (`ui.render` on `UserMessage`, matched on the `task-notification` origin) names that call by its `tool_use_id`, the band says, just after the drawing and unless another run is going, it ended in the background and that its result is in the conversation, or that the task failed or was killed.

The mod runs the build the shim names directly, asking the shim again every 30 s, so the once-a-second poll skips the shim's work; when that build can't be started, the shim runs the command instead. Timing reads nothing itself. While a MobileBuildMCP run goes it asks `xcrew phase` once a second for the run's log and phase; when the call ends it pipes the result to `xcrew report`, which returns the outcome, the failures, the duration, and the shorter result and notes Claude reads.

Beside those, **band** (`ui.render` on `AbovePrompt`) draws the run that timing records in `$.state`, its gauge and phase; a restart the doctor asks for over a finished run; when no run shows, the problem **problems** found with `xcrew doctor --problems --json`. **rows** (`ui.render` on `ToolResult`, matched on either server's tools) draws a finished build or test run's row in the transcript the way the band drew its outcome, with its first failures, while the surface says the row is collapsed. Expanded (ctrl+o), where the surface doesn't say, for an app launch, a failure the CLI couldn't read, or a run this session didn't record, the row is the result Claude read, as the engine draws it; that result is untouched either way. Each row is its own member of a state family, so a run redraws only its own row. **session** is the one unmatched `session.start` hook: it registers `/xcrew` and the ledger, `affected` and `look` tools, starts that look for problems, without holding the session up. **card** saves the project card, at session start and after each run, through `xcrew card --save`, one file per folder and branch; `xcrew hook session-start` prints it at the start of each conversation and after a `/clear` or a compaction. The mod registers no prompt hook: Claude Code passes over a plugin's on some plans (docs/findings.md). The card names the usual durations of the run scopes last run in this folder, the branch's red tests from the ledger, and the selections run before when a full test run is slow, within the caps in `card.ts`. A save the CLI doesn't answer gives way to the next, and a card that hasn't changed isn't saved again. **prompt** is the one unmatched `prompt.submit` hook: it looks again, now and then and never holding the prompt, so a problem fixed any way at all leaves the band. **setup** watches Bash calls that run `xcrew setup` and looks again at once, since setup may have changed the config. Whether a restart is due is the doctor's to say: `mobilebuildmcp/config-loaded` compares when xcrew last wrote the config with when this session's MobileBuildMCP server started.

How long a line stays depends on whether it asks for action. A run shows while it goes; a pass stays a few minutes after it ends, and a failure longer, until the next run, `/xcrew failures` or `/xcrew close`. A failing doctor check stays until a later look finds it fixed; a warning shows for a short while after it's first found, then only in `/xcrew doctor`. The restart line outranks all but a run in progress, until the restart. The durations are the constants in `band.ts` and `problems.ts`. **command** answers `/xcrew` itself: `doctor` runs the CLI, `history` reads timing's durations, kept per tool, scheme and test selection, `failures` opens the **failures** pane, which keeps the last failing run's failures, and `close` closes it. The pane opens only when asked, since docked or above the prompt it takes room from the chat; after a failing run the band ends with `/xcrew failures`.

**ledger** keeps, per branch, the tests seen red and then green. After each test run timing hands it the run's scope, outcome and failures, and it records them in `$.store` under the key `xcrew project --branch` gives: the real root, and the branch, or the commit when HEAD is detached. A failing test, marked by the CLI's `isTest`, enters red. A run that ran every test of its scope turns green each red it covers and didn't fail: the same scope, or a selection of the same tool and scheme's whole suite. A test that fails again goes back to red, keeping its first red but now failing in the new scope. Writes go after the run's result, one at a time, and drop the entries and ledgers no run has written for `HISTORY_KEPT_MS`. A run whose report the CLI couldn't read is left out (docs/findings.md, *The red-to-green ledger*). Claude reads it through a tool the mod registers, `mcp__xcrew__ledger`, behind ToolSearch, and the person through `/xcrew ledger`; both give the same text. **flaky**: a test run whose `extraArgs` hold `-test-iterations` asks `xcrew report --repeated`, which reads each test's `Repetition` nodes from the result bundle and gives each a verdict. The ledger keeps a flaky test red, marked flaky, until a repeated run passes it every time, and the card marks it. **affected** answers the mod's `affected` tool, also behind ToolSearch, from `xcrew affected`: the test targets to select, with their `-only-testing:` arguments, or the whole suite and why. A CLI that can't answer means the whole suite. The routing rules send Claude to it before a full test run. **look** answers the mod's `look` tool with the text of `xcrew look`: for a failed UI test, each failed run's configuration and device, its last steps, its failure, and the screen at it, the last frame of the run's recording, kept as a PNG under the images cache, and the elements on screen from the hierarchy XCTest attached when a query failed, the queried one marked or named missing, then the configurations and devices the test passed under. The routing rules send Claude to it when a UI test fails.

**loop** counts each scope's full-suite runs in `$.state`, as timing ends them. When enough of them, long enough, fall in a short while, it adds a line to the run's result sending Claude to the affected tests, then starts counting again.

Every tool name is matched under both registrations: `mcp__plugin_xcrew_<server>__<tool>` from this plugin, and `mcp__<server>__<tool>` when the person registered the server themselves, which Claude Code then prefers.

### Why `register.ts` holds every `$` call

The plugin directory, and Claude Code when it loads a mod, read a hooks module's calls without running it, and they read `$` only where it stays in one file. Claude Code's docs ([Check what Claude Code reads from your mod](https://code.claude.com/docs/en/plugins/mods/create#check-what-claude-code-reads-from-your-mod)) put it this way:

> You can pass `$` to a function declared at the top level of the same file […] Passing `$` to a method, a function defined inside the hook, or a function you import from another of your files fails validation.

Each `on(...)` call has to be in that file too. And Claude Code's loader reads `$.state` only through atoms declared there; with the atoms in another file, the mod's tests stopped at load with:

> the state library's update takes a source the scan can read: a reference whose plugin and key are string literals, or what atom, memberOf or derive (imported from "claude-code") made of one, written there or in a const of this file, so the values a module reads and writes can be listed; $ is always spelled $.noun.event(...) at the call site, on is always on("<event>", hook), and next.to always next.to(e, "<tier>")

So `register.ts` is the mod's imperative shell and its largest file: the registrations, the state atoms, and a few top-level helpers that take `$` whole. Every other file in `hooks/mod/` is plain data in, data out, with no `$` and no `on`: `cli.ts` says what to run and reads what comes back, `band.ts` and `failures.ts` build their trees from data and the element table a hook passes them, and `timing.ts`, `command.ts`, `problems.ts`, `context.ts`, `format.ts` and `tools.ts` hold the rest. Splitting `register.ts` back into files that take `$` would fail the directory's validation.

### The mod's boundary

The mod does what only TypeScript can reach, and hands everything else to the CLI:

| The mod does | The CLI does |
| --- | --- |
| Register hooks, and decide which calls to act on, by tool name | Read and parse what the servers print as text: results, logs |
| Draw the band and the pane, keep `$.state` and `$.store` | Read files, run `xcrun` and other programs |
| Time calls, and hand a result back to Claude | Decide what a result means and what Claude reads instead |

Reading a few named fields of a JSON answer is fine: **context** learns the scheme and simulator that way. So in `hooks/mod/`:

- Only `register.ts` touches `$` or registers a hook, and passes `$` only to its own top-level functions, each named unlike any other binding in the file: the plugin directory reads a name without regard to scope (`docs/findings.md`).
- One call site starts a process, `start` in `register.ts`, and it runs only the CLI: the build `bin/xcrew --binary-path` names, or the shim. `cli.ts` decides which, with what arguments and time, and reads the answer.
- Only `cli.ts` and `context.ts` parse JSON, only `tools.ts` matches a pattern, and nothing touches the file system.

`ModBoundaryTests` in `Tests/ManifestTests` fails on any of these. When a change seems to need one, the logic belongs in a Swift command the mod calls through `cli.ts`, tested with Swift Testing against captured output in `Tests/XcrewCoreTests/Fixtures`.

### What the mod adds, and how

- One visible thing per surface, hidden when idle, and quiet by default: nothing interrupts unless it's worth it.
- It degrades per surface: a terminal-only element has a fallback in Desktop and VS Code, and nothing draws under `claude -p`.
- Bookkeeping is best-effort and never fails a tool call.
- No token cost goes unstated: anything that adds text to Claude's context says how much.
- Parsing a server's output is tested against captured real outputs, and falls back to the server's own display when it doesn't match.

## Extending

| To add | Write | Then |
| --- | --- | --- |
| A health check | A `Check` in `Sources/XcrewCore/Doctor/Checks/`, listed in `Doctor.checks` | A wrapper in `mcs/checks/` and an entry in `techpack.yaml`; `ManifestTests` fails until both exist |
| A CLI command | A `Command` in `Sources/XcrewCLI/`, listed in `CLI.commands` | Tests in `XcrewCLITests` |
| A setup question | An option in `SetupCommand.mcsKeys` | A prompt in `techpack.yaml`; `ManifestTests` fails until it exists |
| A mod behaviour | Its `on(...)` registration and `$` calls in `register.ts`, and its logic as plain functions in a file of their own in `hooks/mod/` (see *Why `register.ts` holds every `$` call*); anything it needs read or worked out, in a Swift command whose arguments and answer `cli.ts` handles (see *The mod's boundary*) | Tests in `hooks/mod/`, calling tools through `testing.ts` and answering for the CLI with `stubCli`; at most one unmatched hook per event; `scripts/typecheck.sh` clean |
