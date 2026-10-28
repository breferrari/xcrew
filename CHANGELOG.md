# Changelog

## 0.6.3 — 2026-10-28

- A failing MobileBuildMCP test run gives each failure its file and line, in the result Claude gets and in the failure pane. Run on parallel simulator clones, xcodebuild logs failures without them, so the mod reads them from the run's result bundle with `xcresulttool`, one quick lookup per failing test.

## 0.6.2 — 2026-10-28

- A failing MobileBuildMCP test run reaches Claude with its failures and summary, its passing tests counted instead of listed (with `showTestTiming` on, a 959-test run listed every one). A list Claude Code already cut in the middle loses its marker and fragments.
- A test run that ran no tests shows `✗ … no tests ran` instead of a green `✓`, and Claude is told an `-only-testing` filter probably matched nothing: MobileBuildMCP reports such a run as SUCCEEDED.
- The doctor's `macro-copy-phase` warning names the installed Tuist and says whether the fix is to upgrade it or only to regenerate the project.
- The hook spinners read `Preparing Xcode tooling` and `Checking Xcode macro plugins`, without an `xcrew:` prefix.

## 0.6.1 — 2026-10-28

- A large test result now does reach Claude as its summary: 0.6.0 replaced the result's text but kept the reference to Claude Code's own messages, which Claude Code then showed instead. The mod now answers with its own result.
- A MobileBuildMCP run's gauge starts when its log appears, so a pre-build hook's wait no longer shows a normal run as over its usual time. Until then the band says `preparing`.
- `/xcrew history` names a test selection run without a known scheme as `test_sim › AppTests`.

## 0.6.0 — 2026-10-28

- A MobileBuildMCP test result too large for the transcript reaches Claude as its summary, counts, failures and artifacts, with the per-test list left out and the saved file named for it: a 959-test run's 122 KB becomes about 2.5 KB, and Claude no longer needs a `jq` call to read it.

## 0.5.2 — 2026-10-28

- The failure pane clears only when the same tool, scheme and test selection passes, since another scheme's pass never re-ran those tests. Clearing also closes the pane, and `/xcrew close` closes it from the prompt: in Claude Code's default layout (`"tui": "default"`) its close mark can't be clicked; in the fullscreen layout it can.

## 0.5.1 — 2026-10-28

- Before a MobileBuildMCP run's log appears, the band says `preparing` rather than `waiting to start`: the server's own preparation, such as counting tests, happens there too, not only a pre-build hook or a permission prompt.
- The failure pane shows an `XCTFail` as the message it was given, without XCTest's `failed - ` in front.
- `/xcrew history` puts the numbers first, so a long scheme and test selection doesn't push them out of line.

## 0.5.0 — 2026-10-28

- `/xcrew failures` opens a pane listing every failing test and compile error of the last failing run, with its message and where it failed. A later passing run of the same tool clears it.
- When a session starts with something wrong (Xcode MCP not approved, MobileBuildMCP missing, a project still killing macro plugins), the band says so until the first run, with `(+N more)` and where to look. `xcrew doctor --problems` prints only what failed or warned, and nothing outside an Apple-platform project.
- Usual durations, the slow-run note and test totals are kept per scheme and test selection, so testing one module isn't measured against the whole app. Durations recorded before are kept under the tool alone.
- While a build or test run goes, the band draws a gauge of its time against the tool's usual duration, with the time left: `build_sim · 0:21 ━━━━╸─── ~0:15 left`. Past the usual time it turns to the warning colour and counts how far over. It's an estimate: xcodebuild prints no build percentage a mod can read. The first run of a tool shows its time alone.

## 0.4.1 — 2026-10-28

- Until a MobileBuildMCP run's log appears, the band says `waiting to start`, so a pre-build hook or a permission prompt doesn't look like a stalled build. Only tools that have written a log before say it, so `clean` doesn't.
- The phase is shorter and comes before the target: `build_sim · 1:02 · compiling Utility · MyApp on iPhone 17`. The file being compiled is left out, so a narrow terminal cuts the target, which you already know, not the time or the phase.

## 0.4.0 — 2026-10-28

- While a MobileBuildMCP build or test run goes, the band says what it's doing, from the log it writes as it runs: `compiling Utility · Formatter.swift`, `linking Utility`, `testing 431 of 959` against the last run's total. Test results reach the log in batches, so the count moves in steps. The Xcode MCP writes no log to follow.
- Runs are timed by the duration the server reports, so a project's pre-build hook or a permission prompt no longer counts toward a build's time or its average.

## 0.3.0 — 2026-10-28

- The marketplace is named `breferrari`, so the plugin installs as `xcrew@breferrari` rather than `xcrew@xcrew`. An install from 0.2 or earlier is removed and installed again: `claude plugin uninstall xcrew@xcrew`, then `claude plugin install xcrew@breferrari` (the `marketplace add` command is unchanged).
- `/xcrew doctor`, `/xcrew repair` and `/xcrew history` now work: the reference skill, named like the plugin, took the `/xcrew` command, so Claude Code refused the mod's. It's `xcrew:reference` now, and out of the `/` menu.
- `/xcrew history` starts with a heading, so the name Claude Code puts before a command's output doesn't push the first row out of line.

## 0.2.0 — 2026-10-28

- Where the band draws (the terminal, Desktop), it carries a run's outcome alone; the toast that repeated it now shows only where no band draws.
- A result too large for the transcript, which Claude Code saves to a file, is read back from that file, so its outcome still carries its detail (a large project's test run lost its count).
- The status line and band name the scheme after `XcodeSwitchScheme` too, which reports it as `activeSchemeName`.
- A run far slower than usual says so: `(2× its usual 1:50)` once there are five earlier runs, at 1.5× the average or more.
- After a macro-plugin repair, the toast names the projects that will keep killing plugins until Tuist 4.203 or later regenerates them.
- `/xcrew doctor`, `/xcrew repair` and `/xcrew history`, answered by the mod without a turn for Claude.
- In a generated project, `XcodeWrite`'s description says it's refused there, so Claude reaches for Write first.
- The mod type-checks under `strict` (`scripts/typecheck.sh`), on any machine's set of MCP servers.

## 0.1.0 — 2026-10-28

- Plugin with MobileBuildMCP, the Xcode MCP and Sosumi; a session briefing with the routing rules.
- Mod: macro-plugin repair with retry, build and test timing, the `XcodeWrite` guard.
- Swift CLI: `setup`, `doctor`, `repair-macros`, `xcode-skills`, and the hook entry points.
- mcs techpack installing the plugin, MobileBuildMCP and the per-project setup.
- Runs show in colour on a line above the prompt, live and then with their outcome for a few minutes; the plain status line stays as the fallback where that line can't draw.
- The status line names the scheme and simulator a build or test run uses.
- A build or test run of a minute or more also sends its result as a notification.
- The build and test toast says what failed: the first compile error with its file and line, or how many tests failed and the first one. Failed Xcode MCP builds and test runs now count as failures; the server reports them as normal results.
- The doctor names projects still generated with Tuist's pre-4.203 in-place macro copy phase, and the repair message gives that cause and its fix.
- The macro-plugin repair hook runs only when a build fails with the plugin-kill message, and the doctor skips projects with no macro plugins.
- The `XcodeWrite` guard applies only to generated projects; `xcode-skills` keeps a project's own skills of the same name unless `--force`; setup keeps a managed config that was edited by hand; the README installs per project.
- Macro-plugin repair also covers the indexer's build and Swift packages opened directly, and labels the indexer's copies.
- Setup keeps `.mobilebuildmcp/` out of git; the doctor warns when the config points at a workspace that moved; `xcrew --version`; the CLI cache keeps only the current build.
