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

With the [mcs CLI](https://github.com/mcs-cli/mcs), `mcs pack add breferrari/xcrew && mcs sync` does steps 1 to 3 and asks the setup questions.

## What you get

### Builds and tests you can watch

A line above the prompt follows every build and test:

- **While it runs:** elapsed time, a gauge against how long that scheme and test selection usually take, and the phase (`compiling Payments`, `testing 431 of 959`).
- **When it ends:** the outcome, compared with recent runs, and what failed.
- **A run of a minute or more** also sends a notification.
- **Where the line can't draw**, such as VS Code, the status line counts and a toast reports the outcome.

The [image at the top](#readme) shows all four states.

### Test results Claude can act on

A MobileBuildMCP test result can run past 100,000 characters, mostly passing tests. Claude gets the short version:

- **Failures**, each with its file and line, read from the run's result bundle, since xcodebuild logs none for tests on parallel simulators.
- **A crash's exception and top frames**, from the crash log the result bundle attaches.
- **Skipped tests with their reasons**, and **expected failures** that MobileBuildMCP's counts leave out.
- **A warning when a filter matched no tests**, which MobileBuildMCP reports as a success.
- **Compile errors counted once.**
- **Passing tests left out**, with the full list a file read away.

<picture>
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/test-result-light.png">
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/test-result.png">
  <img src="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/test-result.png" alt="What Claude reads from a failing test run: two failures, one with its file and line, one a crash with its exception and top frames; a skipped test with its reason; and the summary" width="100%">
</picture>

### The last failures beside the chat

| Command | What it does |
| --- | --- |
| `/xcrew failures` | Opens a pane with every failing test and compile error of the last failing run. After a failing run the line above the prompt ends with `/xcrew failures`, or the toast does where that line can't draw |
| `/xcrew close` | Closes it |
| `/xcrew history` | Each tool's usual duration, per scheme and test selection; lines no run has updated for weeks are dropped |
| `/xcrew ledger` | The tests seen failing and then passing on the branch checked out, each with the run where it failed and the run that passed it, and those still failing. Claude reads the same through a tool of the mod's, for a pull request's test plan |
| `/xcrew doctor` | The doctor's report, below |

They answer at once, without a turn for Claude.

<picture>
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/failures-pane-light.png">
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/failures-pane.png">
  <img src="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/failures-pane.png" alt="The failures pane beside the chat, listing each failing test with its file, line and message" width="100%">
</picture>

### The right server for each job

Every session in an Apple-platform project starts with this routing, plus anything the project or Mac still lacks:

| Job | Server | Why |
| --- | --- | --- |
| Build, test, coverage, simulators, UI automation, LLDB | MobileBuildMCP | Runs `xcodebuild` with its own DerivedData, so it never fights Xcode's; switchable profiles; test filtering |
| One file's compile errors, SwiftUI previews, code snippets, crash logs, physical devices | Xcode MCP | Uses Xcode's real build settings, which a plain language server can't read in an Xcode project |
| Apple documentation | Sosumi | Short results with each API's minimum OS version |
| Writing files | Claude's own tools | `XcodeWrite` rewrites the whole project file; refused in generated projects |

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
- **`xcrew xcode-skills`** copies the agent skills your Xcode ships (SwiftUI, accessibility, device interaction) into the project. Run it again after an Xcode update.

```
ok    mobilebuildmcp/version           version 2.7.1
ok    mobilebuildmcp/no-legacy-binary  none
ok    mobilebuildmcp/project-config    .mobilebuildmcp/config.yaml
ok    mobilebuildmcp/simulators        iPhone 17
ok    xcode-mcp/headless-enabled       enabled
warn  xcode-mcp/claude-approved        not approved yet: have Claude call XcodeOpenWorkspace, then allow it in Xcode's dialog
ok    xcode-mcp/unsigned-agents-off    off
ok    xcode-mcp/macro-copy-phase       none
ok    xcrew/up-to-date                 0.7.0, the latest release
```

## How it works

<picture>
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/architecture-light.png">
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/architecture.png">
  <img src="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/architecture.png" alt="Claude Code loads the plugin's four pieces: the manifest starts the three MCP servers; the session hook, the mod and the skills call the Swift CLI, which the mcs techpack calls too" width="100%">
</picture>

| Piece | What it does |
| --- | --- |
| MCP servers | MobileBuildMCP (started in your project, telemetry off), the Xcode MCP (`xcrun mcpbridge`), Sosumi |
| Session briefing | The routing rules in [`context/routing.md`](context/routing.md), plus what this project or Mac still lacks; silent outside Apple-platform projects |
| Mod | The live line above the prompt, the failures pane, the `XcodeWrite` guard and a note in its description (in generated projects), the `/xcrew` command. It hands each result to the CLI and passes on what the CLI makes of it |
| Skills | `/xcrew:setup`, and `xcrew:reference`, which Claude loads when something fails (it isn't in the `/` menu) |
| CLI | `xcrew setup`, `doctor`, `xcode-skills`, on Claude's `PATH` while the plugin is enabled; `report` and `phase`, which read the servers' output for the mod |

- **One implementation.** All logic lives in one dependency-free Swift package; the plugin, the mod and mcs call its CLI.
- **No drift.** `Tests/ManifestTests` fails when an install path disagrees with the CLI.
- **More:** [docs/architecture.md](docs/architecture.md) walks through the layout.

## Reference

### Configuration

- **Profiles:** `.mobilebuildmcp/config.yaml` holds `unit` for the scheme that runs your unit tests, which setup finds itself, plus `app` and `ui` when you name those schemes. Each has its scheme and simulator, so it can build as soon as it's active.
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
| **Reads** | Every tool call Claude makes, with its arguments and result, because it hooks `tool.call`. It acts only on the Xcode MCP's and MobileBuildMCP's tools by their names, on Write and Edit calls to a file a generator reads or writes, and on Bash commands that run setup or a generate, and passes every other call on untouched. It keeps each build, test and run's recent durations in Claude Code's own store, with the folder each last ran in, each branch's red-to-green ledger of tests there too, dropped once no run has written it for weeks, and the last failing run's failures for the session |
| **Hooks** | `tool.call`: the `XcodeWrite` guard, the question before an edit to a generated file, the refusal of a build after a manifest edit, the ledger tool's answer, and timing for builds, tests and runs. `tool.describe`: the guard's line in `XcodeWrite`'s description. `ui.render`: the line above the prompt and the failures pane. `command.run`: `/xcrew`. `prompt.context`: the project card in the context of each conversation's first message. `session.start`: registers `/xcrew` and the ledger tool Claude reads, and asks the doctor what's missing |
| **Changes** | In a Tuist or XcodeGen project, it holds `XcodeWrite`, and Write or Edit of a file the generator writes, to ask you, and refuses the call if you say no or nobody can be asked; it says so in `XcodeWrite`'s description. After Claude edits a manifest, it refuses the next build or test, or a run that builds first, once, and adds a line to the edit's result naming the generate command. After a build or test call, Claude reads the CLI's shorter result and notes in place of the server's. At the start of each conversation, it adds a short card to Claude's context: the usual run times in this folder and the tests still failing on the branch, from its own store. Nothing else |
| **Shows** | The line above the prompt, the failures pane, a toast or the status line where the line can't draw, and a notification after a run of a minute or more |
| **Starts** | Only Xcrew's CLI: `bin/xcrew`, or the build it names |
| **Sends** | Nothing. The mod makes no network request |

**The CLI**, which the mod, the session hook, the skills and mcs run:

| | |
| --- | --- |
| **Builds** | Itself, from this repository's Swift source, with `swift build` into `~/Library/Caches/xcrew`, on first use. It has no dependencies, so the build needs no network |
| **Starts** | `xcrun`, to list simulators (`simctl`), check the Xcode MCP (`mcp-server status`), read a test run's result bundle (`xcresulttool`) and find the skills Xcode ships (`mcpbridge`). `defaults`, to read whether Xcode accepts unsigned agents. `git`, to find `.git/info/exclude`, to name the branch or commit checked out, for the ledger, and in a git checkout of Xcrew to show its commit beside the version. `mobilebuildmcp --version` and `tuist version`, for the doctor's checks. `curl`, for the one request below |
| **Reads** | MobileBuildMCP's run logs, a failing or skipped test run's result bundle, `.mobilebuildmcp/config.yaml`, and your project's manifests and Xcode project files, to tell what kind of project it is |
| **Writes** | In `xcrew setup`: `.mobilebuildmcp/config.yaml`, a `.xcrew-managed` marker beside it with the config's fingerprint, a dated backup of a config you edited when you ask it to replace one, and a line in `.git/info/exclude`. In `xcrew xcode-skills`: the skills Xcode ships, into `.claude/skills`. While reading a crashed test, a temporary folder of the crash's attachments, removed once read. Nothing else |
| **Sends** | One request, and only when you run `xcrew doctor` or `/xcrew doctor` yourself: `curl` asks GitHub's releases API for the latest version. Never at session start, whose look for problems leaves that check out. No telemetry |

**The MCP servers**, which the plugin's manifest (`plugin.json`) starts: Apple's `xcrun mcpbridge`, through `libexec/xcode-mcp-server`; Homebrew's `mobilebuildmcp`, through `libexec/mobilebuildmcp-server`, which starts it in your project with Homebrew's folders on `PATH`, and with its telemetry turned off; and Sosumi over HTTPS. Sosumi is a third-party documentation service that receives your documentation searches; see [sosumi.ai](https://sosumi.ai).

### Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) has the setup, the tests and how to add a check, a command or a mod behaviour.

## License

[MIT](LICENSE).
