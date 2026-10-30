<div align="center">

<picture>
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/banner-light.png">
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/banner.png">
  <img src="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/banner.png" alt="Xcrew: a brushed-steel screw with a copper-orange X in its head" width="100%">
</picture>

### Your **Xcode** crew inside **Claude Code**.

**Three MCP servers working as one, with live build progress and test reports Claude can act on.**

[![ci](https://img.shields.io/github/actions/workflow/status/breferrari/xcrew/ci.yml?event=pull_request&style=for-the-badge&label=ci&color=3fb950&labelColor=0d1117)](https://github.com/breferrari/xcrew/actions/workflows/ci.yml) [![canary](https://img.shields.io/github/actions/workflow/status/breferrari/xcrew/canary.yml?branch=main&style=for-the-badge&label=canary&color=3fb950&labelColor=0d1117)](https://github.com/breferrari/xcrew/actions/workflows/canary.yml) [![swift](https://img.shields.io/badge/swift-6.2%2B-f85149?style=for-the-badge&logo=swift&logoColor=white&labelColor=0d1117)](Package.swift) [![xcode](https://img.shields.io/badge/xcode-27%2B-39c5cf?style=for-the-badge&logo=xcode&logoColor=white&labelColor=0d1117)](https://developer.apple.com/xcode/) [![macos](https://img.shields.io/badge/macos-26%2B-8b949e?style=for-the-badge&logo=apple&logoColor=white&labelColor=0d1117)](#quick-start)

</div>

---

Claude Code can build, test and preview Apple apps through Apple's Xcode MCP and MobileBuildMCP, and read Apple's docs through Sosumi. On their own, the three overlap, misroute and bury Claude in output. **Xcrew turns them into one setup, and adds what none of them has.**

<picture>
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/band-light.png">
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/band.png">
  <img src="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/band.png" alt="The line above Claude Code's prompt: a test run with its elapsed time, a gauge and the phase; then a passing run, a failing run and a failed build, each against its usual time" width="100%">
</picture>

| | On their own | With Xcrew |
| --- | --- | --- |
| **Setup** | Three servers to install and register; Claude can pick the wrong one | One install; every session knows which server does what |
| **A build or test run** | A spinner until it ends | [Live progress](#builds-and-tests-you-can-watch): time, a gauge against the usual, the phase |
| **A failing 961-test run** | ~80,000 characters, cut short by Claude Code | [~1,000 characters](#test-results-claude-can-act-on): the failures and the summary |
| **Where a test failed** | Not reported on parallel simulators | The file's absolute path and line |
| **A crash** | The test's name | The exception and the crashed thread's top frames |
| **`XcodeWrite` in a Tuist or XcodeGen project** | Re-saves the whole generated `.pbxproj` | [You're asked first](#a-guard-for-generated-projects); otherwise Claude writes the file itself |
| **An edit to a generated file** | Lost on the next generate | You're asked first, with the manifest to edit instead |
| **A build after a manifest edit** | Builds the project as it was, with errors that don't say why | [Refused once](#a-guard-for-generated-projects), with the generate command to run first |

**Why three servers?** None of them covers everything on its own:

- **MobileBuildMCP** builds and tests with its own DerivedData, so it never touches your Xcode window, and adds coverage, simulators and LLDB.
- **The Xcode MCP** has Xcode's real build settings, for one file's errors, SwiftUI previews and physical devices.
- **Sosumi** answers documentation questions briefly, with each API's minimum OS version.

[docs/findings.md](docs/findings.md) has the measurements.

Works in any Apple-platform project: plain Xcode, Tuist or XcodeGen. [Install it in two minutes ↓](#quick-start)

## Quick start

You need macOS 26 or later, Xcode 27 or later, [Homebrew](https://brew.sh) and [Claude Code](https://claude.com/claude-code).

1. **Install the plugin** in your project. Use project or local scope, since its servers are only useful in Apple-platform projects:

   ```sh
   claude plugin marketplace add breferrari/xcrew
   claude plugin install xcrew@breferrari --scope project   # or --scope local: this project, only you
   ```

2. **Prepare the Mac**, once:

   ```sh
   brew install getsentry/xcodebuildmcp/mobilebuildmcp
   sudo xcrun mcp-server enable
   ```

3. **Restart Claude Code** in your project and run `/xcrew:setup`. The first run builds Xcrew's small Swift CLI, 10 to 20 seconds, once per version.

4. **Approve Claude Code in Xcode's dialog** the first time Claude calls the Xcode MCP.

With the [mcs CLI](https://github.com/mcs-cli/mcs), `mcs pack add breferrari/xcrew --ref stable && mcs sync` does steps 1 to 3 and asks the setup questions.

## What you get

### Builds and tests you can watch

A line above the prompt follows every build and test:

- **While it runs:** elapsed time, a gauge against how long that scheme and test selection usually take, and the phase (`compiling Payments`, `testing 431 of 959`).
- **When it ends:** the outcome, compared with recent runs, and what failed.
- **A long run** also sends a notification.
- **Where the line can't draw**, such as VS Code, the status line counts and a toast reports the outcome.

The [image at the top](#your-xcode-crew-inside-claude-code) shows all four states.

### Test results Claude can act on

A MobileBuildMCP result for a failing run of a large suite runs to about 80,000 characters, mostly passing tests. Claude gets the short version:

- **Failures**, each with its file and line, read from the run's result bundle, since xcodebuild logs none for tests on parallel simulators.
- **A crash's exception and top frames**, from the crash log the result bundle attaches.
- **Skipped tests with their reasons**, and **expected failures** that MobileBuildMCP's counts leave out.
- **A warning when a filter matched no tests**, which MobileBuildMCP reports as a success.
- **Flaky or real**: a test repeated with `-test-iterations` comes back with a verdict for each test. It's flaky when it failed some runs and passed others, and a real failure when it failed every run.
- **Warnings in lines your branch changed**, named apart from the rest of a build's warnings.
- **The changed lines a test run didn't run**, from its coverage, on a run with coverage on.
- **A loop budget**: after the whole suite runs again and again in a short while, Claude is sent to the tests the change can break.
- **Compile errors counted once.**
- **Passing tests left out**, with the full list a file read away.

<picture>
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/test-result-light.png">
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/test-result.png">
  <img src="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/test-result.png" alt="What Claude reads from a failing test run: two failures, one with its file and line, one a crash with its exception and top frames; a skipped test with its reason; and the summary" width="100%">
</picture>

### The last failures beside the chat

After a failing run, the line above the prompt ends with `/xcrew failures`, or the toast does where that line can't draw. It opens the failures pane, with every failing test and compile error of the last failing run.

<picture>
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/failures-pane-light.png">
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/failures-pane.png">
  <img src="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/failures-pane.png" alt="The failures pane beside the chat, listing each failing test with its file, line and message" width="100%">
</picture>

### Commands

**Setting up**

| Command | What it does |
| --- | --- |
| `/xcrew:setup` | Writes MobileBuildMCP's per-project profiles from your schemes and installed simulators |
| `xcrew xcode-skills` | Copies the agent skills your Xcode ships into the project |

**Around a run**

| Command | What it does |
| --- | --- |
| `xcrew affected` | The tests your branch's changes can break |
| `/xcrew failures` | Opens the failures pane, with every failing test and compile error of the last failing run. After a failing run the line above the prompt ends with `/xcrew failures`, or the toast does where that line can't draw |
| `/xcrew close` | Closes the failures pane |
| `/xcrew ledger` | The tests seen failing and then passing on the branch checked out, each with the run where it failed and the run that passed it, and those still failing. Claude reads the same through a tool of the mod's, for a pull request's test plan |
| `/xcrew history` | Each tool's usual duration, per scheme and test selection; lines no run has updated for weeks are dropped |

**When something's off**

| Command | What it does |
| --- | --- |
| `/xcrew doctor`, `xcrew doctor` | The doctor's report: in the chat, or in a terminal with the fix for anything wrong |
| `xcrew xcode` | Which Xcode is which: those installed, the selected one, the project's pin, CI's, and the one open |

Commands starting with `/` are typed in Claude Code, the rest in a terminal. The `/xcrew` commands answer at once, without a turn for Claude.

### The right server for each job

Every session in an Apple-platform project starts with this routing, plus anything the project or Mac still lacks:

| Job | Server | Why |
| --- | --- | --- |
| Build, test, coverage, simulators, UI automation, LLDB | MobileBuildMCP | Runs `xcodebuild` with its own DerivedData, so it never fights Xcode's; switchable profiles; test filtering |
| One file's compile errors, SwiftUI previews, code snippets, crash logs, physical devices | Xcode MCP | Uses Xcode's real build settings, which a plain language server can't read in an Xcode project |
| Apple documentation | Sosumi | Short results with each API's minimum OS version |
| Writing files | Claude's own tools | `XcodeWrite` rewrites the whole project file; in a generated project you're asked first |

- **When MobileBuildMCP isn't usable**, because it's missing or older than Xcrew needs, the session sends builds to the Xcode MCP's `BuildProject` and tests to `RunAllTests`. They work through the open Xcode, its active scheme and its own DerivedData, and Claude tells you once what's lost meanwhile: coverage, simulator control, UI automation and LLDB.
- **Simulators already booted** are named at the start, so Claude reuses one rather than booting another.
- **A card at session start:** each conversation starts with a short card in Claude's context: how long builds and test runs usually take in this folder, the tests still failing on the branch, flaky ones marked, and, when a full test run is slow, the selections run before. It's built from what Xcrew already recorded, sent once per conversation, and kept to a few lines.

[docs/findings.md](docs/findings.md) has the evidence behind each choice, and what was tried and rejected.

### A guard for generated projects

- **In a Tuist or XcodeGen project:** the Xcode MCP's `XcodeWrite` re-saves the whole generated `.pbxproj`, so Xcrew asks you before it runs, and points Claude at its own Write tool if you say no.
- **Edits to what a generator writes:** before Claude edits a file inside a generated `.xcodeproj` or `.xcworkspace`, or in Tuist's `Derived` folder, Xcrew asks you: the next generate overwrites the edit. Say no, and Claude is told to edit the manifest instead, named, and the generate command to run. Where nobody can be asked, as in `claude -p`, the edit is refused with that reason.
- **In a classic Xcode project:** it stays allowed, since that's how a new file joins its target.
- **After Claude edits a manifest** (`Project.swift`, `Tuist.swift`, `project.yml` and the like): the next build or test, or a run that builds first, is refused once, with the command that regenerates the project, such as `tuist generate --no-open`. Once that command succeeds, builds run again. If you generated in your own terminal, the next attempt goes through.

### Setup and doctor

- **`/xcrew:setup`** writes MobileBuildMCP's per-project profiles from your schemes and installed simulators.
- **`xcrew doctor`** checks the Mac and the project, prints the fix for anything wrong, and says when a newer Xcrew is out.
- **Anything wrong** shows in the line above the prompt: a failing check until it's fixed, however you fix it, and a warning for a short while. When setup or `mcs sync` changed the config after MobileBuildMCP started, the line asks you to restart Claude Code.
- **`xcrew xcode`** says which Xcode is which: those installed, the selected one, the project's `.xcode-version` pin, CI's, and the one open. A pinned Xcode is the one MobileBuildMCP builds and tests with.
- **`xcrew xcode-skills`** copies the agent skills your Xcode ships (SwiftUI, accessibility, device interaction) into the project. Run it again after an Xcode update.
- **`xcrew affected`** lists the tests your branch's changes can break: the test targets of every target that owns a changed file or depends on one, at any depth, as the project declares them. When a change touches what it can't read (the project file, a scheme, an `.xcconfig`, a package or a manifest), it says to run everything, and why. Claude asks it before running the whole suite, through a tool of the mod's.

```
ok    mobilebuildmcp/version           version 2.7.1
ok    mobilebuildmcp/no-legacy-binary  none
ok    mobilebuildmcp/project-config    .mobilebuildmcp/config.yaml
ok    mobilebuildmcp/config-loaded     loaded at its start
ok    mobilebuildmcp/simulators        iPhone 17
ok    xcode-mcp/headless-enabled       enabled
ok    xcode/pin                        Xcode 27.2, at /Applications/Xcode-27.2.app
ok    xcode/ci                         CI uses Xcode 27.2 too
ok    xcode/open                       the open Xcode 27.2 is the one MobileBuildMCP builds with
warn  xcode-mcp/claude-approved        not approved yet: have Claude call XcodeOpenWorkspace, then allow it in Xcode's dialog
ok    xcode-mcp/unsigned-agents-off    off
ok    xcode-mcp/macro-copy-phase       none
ok    xcrew/up-to-date                 0.8.9, the latest release
```

## How it works

<picture>
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/architecture-light.png">
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/architecture.png">
  <img src="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/architecture.png" alt="Claude Code loads the plugin's four pieces: the manifest starts the three MCP servers; the session hook, the mod and the skills call the Swift CLI, which the mcs techpack calls too" width="100%">
</picture>

| Piece | What it does |
| --- | --- |
| MCP servers | MobileBuildMCP (started in your project, telemetry off, with the project's pinned Xcode), the Xcode MCP (`xcrun mcpbridge`), Sosumi |
| Session briefing | The routing rules in [`context/routing.md`](context/routing.md), plus what this project or Mac still lacks, the pinned Xcode, the simulators booted, and where builds go when MobileBuildMCP isn't usable; silent outside Apple-platform projects. `xcrew hook` writes it |
| Mod | The live line above the prompt, the failures pane, the project card, the `XcodeWrite` and generated-file guards and a note in `XcodeWrite`'s description (in generated projects), the refusal of a build after a manifest edit, the `/xcrew` command, and the `affected` and ledger tools Claude asks. It hands each result to the CLI and passes on what the CLI makes of it |
| Skills | `/xcrew:setup`, and `xcrew:reference`, which Claude loads when something fails (it isn't in the `/` menu) |
| CLI | `xcrew setup`, `doctor`, `xcode`, `affected`, `xcode-skills`, on Claude's `PATH` while the plugin is enabled; `report`, `phase` and `project`, which read the servers' output and the project for the mod and the skills |

- **One implementation.** All logic lives in one dependency-free Swift package; the plugin, the mod and mcs call its CLI.
- **No drift.** `Tests/ManifestTests` fails when an install path disagrees with the CLI.
- **More:** [docs/architecture.md](docs/architecture.md) walks through the layout.

## Reference

### Configuration

- **Profiles:** `.mobilebuildmcp/config.yaml` holds `unit` for the scheme that runs your unit tests, which setup finds itself, plus `app` and `ui` for your app and UI-test schemes: `/xcrew:setup` picks those from your schemes and asks you to confirm, and `xcrew setup` takes them as `--app-scheme` and `--ui-scheme`. Each has its scheme and simulator, so it can build as soon as it's active.
  - Rerun `/xcrew:setup` or `xcrew setup` to change them.
  - A config Xcrew didn't write is left alone, unless you pass `--force`, which keeps a backup.
  - It holds this Mac's absolute paths, so setup keeps it out of git through `.git/info/exclude`.
- **Your own server entries:** Claude Code prefers your `xcode` and `MobileBuildMCP` entries over the plugin's. Remove yours with `claude mcp remove <name>`, or keep them: the mod works with either.

### Troubleshooting

Run `xcrew doctor` first; every line that isn't `ok` names its fix. Beyond that:

| Symptom | Cause | Fix |
| --- | --- | --- |
| Every Xcode MCP call fails with "not approved" | Xcode asks once per agent | Have Claude call `XcodeOpenWorkspace`; allow it in Xcode's dialog |
| MobileBuildMCP has only simulator tools | No `.mobilebuildmcp/config.yaml` in the project | `/xcrew:setup`, then restart Claude Code |
| `No such module 'UIKit'` from SourceKit | Claude Code's language server can't read Xcode projects | Ignore it; the Xcode MCP's diagnostics are the real ones |
| A build fails with "produced malformed response" | Usually a macro plugin macOS killed. Tuist before 4.203 generated a phase that overwrites plugins in place; `xcrew doctor` names the projects | Upgrade Tuist to 4.203 or later and regenerate. Until then, clean the build folder and rebuild |
| A session starts with an `xcrew: building the CLI` error | The Swift toolchain is older than 6.2, or Xcode's command-line tools aren't selected | `xcode-select -p` should point into Xcode 27; `sudo xcode-select -s /Applications/Xcode.app` |
| A hand edit to `.mobilebuildmcp/config.yaml` seems ignored | MobileBuildMCP reads it only when it starts, and xcrew can't tell your edit from MobileBuildMCP saving its own defaults | Restart Claude Code |
| `project-config` warns the config points at a missing workspace | The project moved or the workspace was renamed | `/xcrew:setup` |

### Updating and removing

**Updating**

Installs follow the `stable` branch, which moves only when a version is released, so updates arrive with each release, not with each change merged.

- **Automatically:** `/plugin` → **Marketplaces** → `breferrari` → **Enable auto-update**. Claude Code leaves it off for marketplaces like this one.
- **By hand:** `claude plugin marketplace update breferrari && claude plugin update xcrew@breferrari`.
- **With the mcs CLI:** `mcs check-updates` says when a new version is out, and `mcs update` installs it.
- `xcrew doctor` says when a newer release is out. The CLI rebuilds once for the new version.

**Removing**

1. `/plugin uninstall xcrew@breferrari`, or remove the pack with the mcs CLI.
2. Optionally, `rm -rf .mobilebuildmcp` in each project (and its line in `.git/info/exclude`), `rm -rf ~/Library/Caches/xcrew`, and `brew uninstall mobilebuildmcp`.
3. To revoke Claude Code's access to Xcode: find its id in `xcrun mcp-server status`, then `sudo xcrun mcp-server deny <id>`. `sudo xcrun mcp-server disable` turns headless mode off.

### Privacy

Everything Xcrew reads, runs, changes and sends on your Mac. Nothing in it reads a token, a key or a password, and it never runs anything with `sudo`: the one `sudo` command, in *Quick start*, is yours to run.

**The mod**, which runs inside Claude Code:

| | |
| --- | --- |
| **Reads** | Every tool call Claude makes, with its arguments and result, because it hooks `tool.call`. It acts only on the Xcode MCP's and MobileBuildMCP's tools by their names, on Write and Edit calls to a file a generator reads or writes, and on Bash commands that run setup or a generate, and passes every other call on untouched. It keeps, in Claude Code's own store, each build, test and run's recent durations, with when each last ran and the folder each last ran in, how many tests each test run ran and whether its server writes a log to follow, and each branch's red-to-green ledger of tests, with flaky tests marked, dropped once no run has written it for weeks. For the session only, it keeps the run in progress, the last failing run's failures, the recent whole-suite runs the loop budget counts, the doctor's latest problems, which build of the CLI to run, each build or test result's row, and the generate command a manifest edit is waiting on |
| **Hooks** | `tool.call`: the `XcodeWrite` guard, the question before an edit to a generated file, the refusal of a build after a manifest edit, the `affected` and ledger tools' answers, timing for builds, tests and runs, and, after a setup or generate command in Bash, a look for problems and whether the project is up to date. `tool.describe`: the guard's line in `XcodeWrite`'s description. `ui.render`: the line above the prompt, the failures pane, and the row a build or test result shows in the transcript. `command.run`: `/xcrew`. `prompt.context`: the project card in the context of each conversation's first message. `prompt.submit`: after a prompt, at most every so often, asks the doctor again what's missing, for the line above the prompt. `session.start`: registers `/xcrew` and the ledger and `affected` tools Claude reads, and asks the doctor what's missing |
| **Changes** | In a Tuist or XcodeGen project, it holds `XcodeWrite`, and Write or Edit of a file the generator writes, to ask you, and refuses the call if you say no or nobody can be asked; it says so in `XcodeWrite`'s description. After Claude edits a manifest, it refuses the next build or test, or a run that builds first, once, and adds a line to the edit's result naming the generate command. After a build or test call, Claude reads the CLI's shorter result and notes in place of the server's. At the start of each conversation, it adds a short card to Claude's context: the usual run times in this folder and the tests still failing on the branch, from its own store. Nothing else |
| **Shows** | The line above the prompt, the failures pane, a row with each build or test result, a toast or the status line where the line can't draw, and a notification after a long run |
| **Starts** | Only Xcrew's CLI: `bin/xcrew`, or the build it names |
| **Sends** | Nothing. The mod makes no network request |

**The CLI**, which the mod, the session hook, the skills, the MobileBuildMCP launcher and mcs run:

| | |
| --- | --- |
| **Builds** | Itself, from this repository's Swift source, with `swift build` into `~/Library/Caches/xcrew`, on first use. It has no dependencies, so the build needs no network |
| **Starts** | `xcrun`, to list simulators (`simctl`), check the Xcode MCP (`mcp-server status`), read a test run's result bundle (`xcresulttool`) and its coverage (`xccov`), and find the skills Xcode ships (`mcpbridge`). `defaults`, to read whether Xcode accepts unsigned agents. `git`, to find `.git/info/exclude`, to name the branch or commit checked out, for the ledger, to list what the branch changed since it left the main branch (`merge-base`, `diff`), for affected tests and for warnings and coverage in changed lines, and in a git checkout of Xcrew to show its commit beside the version. `mdfind` (Spotlight) and `xcode-select -p`, to find the installed Xcodes and the selected one. `ps` and `lsof`, to find the MobileBuildMCP serving this project, when it started, and the open Xcode. `pgrep`, to see whether any simulator runs before listing the booted ones. `plutil`, to read how many displays a simulator has. `mobilebuildmcp --version` and `tuist version`, for the doctor's checks. `curl`, for the one request below |
| **Reads** | MobileBuildMCP's run logs, a failing or skipped test run's result bundle and a test run's coverage, `.mobilebuildmcp/config.yaml`, your project's manifests and Xcode project files, to tell what kind of project it is, its `.xcode-version` and CI workflows, and each installed Xcode's version from its bundle |
| **Writes** | In `xcrew setup`: `.mobilebuildmcp/config.yaml`, a `.xcrew-managed` marker beside it with the config's fingerprint, a dated backup of a config you edited when you ask it to replace one, and a line in `.git/info/exclude`. In `xcrew xcode-skills`: the skills Xcode ships, into `.claude/skills`. In `~/Library/Caches/xcrew`: its own build, and the installed MobileBuildMCP's version, kept until MobileBuildMCP changes. While reading a crashed test, a temporary folder of the crash's attachments, removed once read. Nothing else |
| **Sends** | One request, and only when you run `xcrew doctor` or `/xcrew doctor` yourself: `curl` asks GitHub's releases API for the latest version. Never at session start, whose look for problems leaves that check out. No telemetry |

**The MCP servers**, which the plugin's manifest (`plugin.json`) starts: Apple's `xcrun mcpbridge`, through `libexec/xcode-mcp-server`; Homebrew's `mobilebuildmcp`, through `libexec/mobilebuildmcp-server`, which starts it in your project with Homebrew's folders on `PATH`, and with its telemetry turned off; and Sosumi over HTTPS. When the project pins an Xcode in `.xcode-version`, the launcher asks the CLI for that Xcode (`xcrew xcode --developer-dir`) and starts MobileBuildMCP with `DEVELOPER_DIR` set to it; it writes what came of that to `~/Library/Caches/xcrew/launches`, which the doctor reads. Sosumi is a third-party documentation service that receives your documentation searches; see [sosumi.ai](https://sosumi.ai).

### Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) has the setup, the tests and how to add a check, a command or a mod behaviour.

## License

[MIT](LICENSE).
