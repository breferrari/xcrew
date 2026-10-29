# Changelog

## Unreleased

- In a Tuist or XcodeGen project, after Claude edits a manifest, the next build or test, or a run that builds first, is refused once with the command that regenerates the project, such as `tuist generate --no-open`, so it doesn't build the project as it was. With several Tuist apps in one repository, each app edited needs its own generate, and the refusal names every one still to run. A generate that succeeds lets builds run again; if you generated in your own terminal, the next attempt goes through. After a change to `Tuist/Package.swift`, the command runs `tuist install` first. A source file that only shares a manifest's name, like a `Project.swift` model, doesn't count.

## 0.8.6 — 2026-10-29

- When MobileBuildMCP is missing or out of date, the session briefing has Claude build and test through the Xcode MCP and tell you once what that loses (coverage, simulator control, UI automation, LLDB), instead of stopping at "install it". It asks before switching your open Xcode to another scheme.

## 0.8.5 — 2026-10-29

- The line above the prompt follows only its own run, so two sessions building in one checkout, or in two checkouts of folders with the same name, no longer show each other's progress.
- `xcrew doctor` finds the in-place macro copy phase older Tuist generated in a project saved in Xcode 27.2's JSON format too, not only in `project.pbxproj`, and warns as it does there.
- Installs now follow a `stable` branch that each release moves forward, in place of a tag the marketplace names, so a release reaches `claude plugin update` the moment it is published.

## 0.8.4 — 2026-10-29

- A build or test call's row in the transcript shows its outcome, as the line above the prompt does: `✓ test_sim · 1:12 · 959 passed`, or the first failures and how many more. ctrl+o shows the result Claude read, which is unchanged.
- The line above the prompt asks you to restart Claude Code whenever setup or `mcs sync` wrote the config after MobileBuildMCP started, and stops once you have. `xcrew doctor` has the check: `mobilebuildmcp/config-loaded`. A hand edit still needs a restart by hand. Setup no longer rewrites a config that hasn't changed.
- A compiler warning that fires in several places reaches Claude once, with how many times and every file and line, in place of one copy of the message per place. Warnings that differ are left as MobileBuildMCP wrote them.
- The session briefing tells Claude to leave DerivedData alone unless you ask, and to report a build that looks corrupted instead. It also says to build, test and drive simulators through MobileBuildMCP rather than `xcodebuild` or `simctl` in Bash, which stays for your own build scripts and what no tool covers, such as archiving.
- The session briefing names the simulators booted now, when any are, so Claude reuses one rather than booting another.
- A large test result that Claude Code saved to a file is still read back and shortened if a later Claude Code words its notice differently: xcrew finds the file by its path rather than the notice's sentence.
- `/xcrew history` drops a line no run has updated for two weeks, so lines in a format an older version wrote stop showing beside today's, and month-old runs no longer count toward a build's usual time.
- The notification after a long failing run carries its outcome alone, without the `/xcrew failures` pointer, which can't be typed from a notification. The line above the prompt, and the toast where that line can't draw, still end with it.
- `xcrew doctor`'s exit status no longer depends on which check comes first: 1 when one failed, 2 when one warned, 3 only when every check skipped, else 0. A skipped first check used to make a clean run exit 3.

## 0.8.3 — 2026-10-29

- `/xcrew:setup` now asks which folder to use when two qualify, or tells you to generate a Tuist project first, and no longer mistakes a doctor warning for a failed setup.
- `xcrew setup` picks a standard iPhone simulator again. A device with its own runtime, such as the iPhone Duo with Xcode 27.2, no longer looks newer than the rest, and a simulator with two displays is never the default, since screenshots fail on it. `xcrew doctor` warns when your config already names one.
- After `/xcrew:setup` writes the config, the line above the prompt asks you to restart Claude Code.
- The line above the prompt keeps itself current. A passed run leaves after 3 minutes, a failed one when you look at it or after 30. A failing check stays until it's fixed, however you fix it; a warning shows for two minutes.
- A fix text mentions mcs only in a project set up through mcs.

## 0.8.2 — 2026-10-29

- `xcrew setup` writes only profiles that have a scheme, finds your unit-test scheme itself, and writes each profile's simulator ID, so `screenshot` works after a profile switch. `xcrew doctor` flags configs from 0.8.1 and earlier: rerun `/xcrew:setup`.
- A fresh install from the marketplace now gets the tagged release, not the newest code on main under the last release's version. `xcrew doctor` also shows the commit beside the version when Xcrew runs from a git checkout.
- `xcrew doctor`'s fix for a missing MobileBuildMCP config now says "the mcs CLI": on a Mac with Mono, a bare `mcs` is Mono's C# compiler.
- The first run now says building Xcrew's CLI takes 10 to 20 seconds, instead of "about 10 s".

## 0.8.1 — 2026-10-29

- Xcrew builds with Swift 6.2 (Xcode 26.0) again, the oldest toolchain it supports. Since 0.7.2, one line in how it reads a test run needed Swift 6.3 to compile, so the first build failed on Xcode 26.0 and 26.0.1.
- The line above the prompt is easier to read: the time, the time left, the phase, the result and the scheme and simulator are in your theme's text colour, and only the separators between them stay faint. On a finished run, the scheme and simulator come last, as they do while it runs, so a narrow terminal cuts them before the outcome.
- A script that runs `xcrew hook` or `xcrew report` and leaves standard input open no longer waits forever: xcrew stops reading once two seconds pass with nothing new, says so on stderr, and goes on. A file passed on standard input is read at once. Claude Code closes the input, so it was never affected.

## 0.8.0 — 2026-10-29

- **Apps a folder or two below the root.** In a git repository, an app kept in `ios/`, `apps/ios/` or `apps/MyApp.iOS/` counts as an Apple-platform project: Claude gets the session briefing and the line above the prompt shows the doctor's problems. `xcrew setup` without `--container` finds its workspace or project there too. In a generated project it takes the one beside the manifests and says `generate it first` when that isn't there yet. When two folders hold projects equally near (`apps/ios/`, `apps/macos/`), it names them and asks for `--container`.
- **Generated projects, told apart more carefully.** A source file named `Project.swift` or `Workspace.swift` below the root no longer marks a classic project as Tuist-generated, so Claude can edit its project files again. A Tuist app found by its git root alone is still guarded. The doctor finds Tuist's old macro copy phase in every Tuist app in the project, not only at the root.
- **The project search** finds a project opened through a symlink again, and never walks your home folder, however its path is spelled and wherever it sits.
- **`xcrew doctor` outside an Apple-platform project** skips the two project checks (`not an Apple project`) instead of failing them and suggesting setup.
- **`xcrew <command> --help`** prints that command's usage. An option or word a command doesn't take is refused with exit 64 instead of being ignored: `xcrew doctor --help`, `-l` or `problems` used to run every check.
- **Build, test and run tools are recognised by whole words in their names.** A tool with *latest* in its name is no longer timed as a test run, while `RunTargetTests`, `RunUITests`, `swift_package_build` and `launch_mac_app` are timed. Switching the test plan (`XcodeSwitchTestPlan`) and tools that only read, such as `build_settings`, aren't timed.
- **A build or test call that fails beneath Xcrew**, such as one that's interrupted, no longer leaves the line above the prompt or the status line counting.
- **A command Xcrew runs that exits while a background process it started keeps running** no longer holds Xcrew up until that process ends: Xcrew gives the command's output a second to arrive, then goes on.
- **The README's new *Privacy* section** lists everything Xcrew reads, runs, changes and sends, and the plugin's privacy link opens it.
- **The Xcode MCP and MobileBuildMCP** now start from small scripts in the plugin, in `libexec/`. What they do doesn't change.

## 0.7.3 — 2026-10-29

- After a failing build or test run, the line above the prompt ends with `/xcrew failures`, which opens the pane listing each failure.

## 0.7.2 — 2026-10-29

- The mod runs the CLI's build directly, about 5 ms a call instead of about 35 ms through `bin/xcrew`, which matters most for the band's once-a-second phase. `bin/xcrew` itself no longer hashes the sources on every call: it keeps the key in its cache and works it out again only when a source changes.
- A call you deny at the permission prompt leaves no trace: no time in the usual-duration history, no outcome line, no notification.
- A build killed outright no longer leaves a lock that holds up every Xcrew call for ten minutes.
- A Tuist project with a root `Tuist.swift`, or with its manifests a folder or two below the root (`ios/`), counts as generated: the `XcodeWrite` guard and the doctor's copy-phase check both find it.
- Any MobileBuildMCP `session_` answer and any Xcode MCP switch answer updates the scheme and simulator the band shows, such as `session_clear_defaults`.
- The band follows its own project's log, not another project whose name starts the same (`App` and `App-Legacy`).
- On a crash-heavy run, Xcrew looks up at most four tests at once, so a busy Mac doesn't time its lookups out.
- The band's phase stays fast when a log ends in a long run of warnings.
- The band's phase stays cheap on a clean build: it reads the end of the log, not all of it. A 45 MB log took 1.4 s a second to read; now it takes 0.07 s.
- Session start is faster outside Tuist projects: the doctor looks for Tuist's old macro copy phase only where Tuist generated the project. It took about 0.7 s in a large project.
- The installed plugin and a development checkout no longer rebuild each other's CLI in turn: a cached build is removed after two weeks unused, not whenever another version builds. Two first runs at once now build once.
- `xcrew doctor --problems` lists failures before warnings.
- With mcs, the techpack no longer runs its own check for a newer Xcrew: `mcs check-updates` already reports pack updates, and `mcs update` installs them. `xcrew doctor` keeps the check for plugin installs.
- The note about a run's expected failures names the tests, five at most.
- A crashed test whose run attached no crash log says so, and how to get one, so Claude knows why there are no frames.
- `xcrew doctor --problems` prints `No problems.` when there are none, rather than nothing.

## 0.7.1 — 2026-10-29

- A test run that fails to compile counts each compile error once, as a build does: the compiler's caret line was counted as a second error.
- Installing or syncing Xcrew with mcs works again: 0.7.0's new description made `techpack.yaml` invalid YAML, so mcs couldn't load the pack.

## 0.7.0 — 2026-10-29

- The macro-plugin repair is gone: the mod's retry, the hooks after a failed Xcode MCP build, `/xcrew repair`, `xcrew repair-macros` and the doctor's `xcode-mcp/macro-plugins` check. Finding a dead plugin meant launching every macro plugin in DerivedData, and the cause, the in-place copy phase Tuist generated before 4.203, is gone from current Tuist. `xcrew doctor` still names projects generated with that phase, with the fix: upgrade Tuist and regenerate. `XCREW_MACRO_PLUGINS` and `XCREW_DERIVED_DATA` no longer do anything.
- The README describes Xcrew as it is now, leading with what it changes: one setup for the three servers, builds and tests you can watch, and test results Claude can act on, for any Apple-platform project. Drawn mockups show the line above the prompt, a compact test result, the failures pane and how the pieces fit together.
- The plugin's description, in the plugin list and on the techpack listing, now reads "Your Xcode crew inside Claude Code: three MCP servers working as one, with live build progress and test reports Claude can act on."

## 0.6.10 — 2026-10-28

- A skipped test reaches Claude with its reason even when MobileBuildMCP leaves it out of its Test Results list, which it can in a run that also crashes or records expected failures: the skipped tests and their reasons now come from the result bundle's test list, in one `xcresulttool` call rather than one per test.

## 0.6.9 — 2026-10-28

- `xcrew doctor` (and `/xcrew doctor`) checks whether a newer Xcrew is out, against the latest GitHub release, and says how to update or turn on auto-update. It's the only check that reaches the network: the session-start look for problems leaves it out, and it skips rather than fails when GitHub can't be reached.
- The README says how to turn on auto-update, which Claude Code leaves off for third-party marketplaces.

## 0.6.8 — 2026-10-28

- A skipped test's reason reaches Claude in a long failing run too: 0.6.6 and 0.6.7 looked it up, then dropped it when they compacted the Test Results list.

## 0.6.7 — 2026-10-28

- A MobileBuildMCP test run with expected failures (`XCTExpectFailure`) tells Claude how many ran, and the true total: MobileBuildMCP's counts leave them out.

## 0.6.6 — 2026-10-28

- A crashed test reaches Claude with the crash's exception and the top frames of the thread that crashed, from the crash log its result bundle attaches.
- A skipped test reaches Claude with why it was skipped, from its result bundle.
- A compile error is counted once: MobileBuildMCP also listed the compiler's caret line as an error of its own.
- A compacted failing run lists its failures once, under Test Failures, rather than again under Test Results, where the parallel runners' log can miss some; and the note for a left-out per-test list no longer gives a count that can disagree with the summary's.

## 0.6.5 — 2026-10-28

- A compacted failing run keeps its skipped tests' lines (`⏭️`) beside the failing ones; 0.6.2 to 0.6.4 left them out with the passing tests, so a skipped test showed only in the count.

## 0.6.4 — 2026-10-28

- The plugin list shows the plugin as `xcrew`, its id, like the `xcode` server: the capitalised Xcrew stays for the README and the techpack card.

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
