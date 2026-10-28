<div align="center">

<img src="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/banner.png" alt="Xcrew: a brushed-steel screw with a copper-orange X in its head" width="100%">

### The crew that gets **Claude Code** working with **Xcode**.

**One install sets up Apple's Xcode MCP, MobileBuildMCP and Sosumi for your Apple-platform project, shows every build and test live, and hands Claude results it can act on.**

[![ci](https://img.shields.io/github/actions/workflow/status/breferrari/xcrew/ci.yml?event=pull_request&style=for-the-badge&label=ci&color=3fb950&labelColor=0d1117)](https://github.com/breferrari/xcrew/actions/workflows/ci.yml) [![canary](https://img.shields.io/github/actions/workflow/status/breferrari/xcrew/canary.yml?branch=main&style=for-the-badge&label=canary&color=3fb950&labelColor=0d1117)](https://github.com/breferrari/xcrew/actions/workflows/canary.yml) [![swift](https://img.shields.io/badge/swift-6.2%2B-f85149?style=for-the-badge&logo=swift&logoColor=white&labelColor=0d1117)](Package.swift) [![xcode](https://img.shields.io/badge/xcode-27%2B-39c5cf?style=for-the-badge&logo=xcode&logoColor=white&labelColor=0d1117)](https://developer.apple.com/xcode/) [![macos](https://img.shields.io/badge/macos-26%2B-8b949e?style=for-the-badge&logo=apple&logoColor=white&labelColor=0d1117)](#quick-start)

</div>

---

Each of the three servers is good at something different, and side by side they overlap, misroute and bury Claude in output. Xcrew makes them one setup:

- **The right server for each job.** Every session in an Apple-platform project starts knowing which server builds and tests, which compiles one file or renders a preview, which knows the docs, and which tool never to touch.
- **Builds and tests you can watch.** A line above the prompt shows the run as it goes: elapsed time, a gauge against how long that scheme usually takes, and the phase (`compiling Payments`, `testing 431 of 959`). When it ends, the same line gives the outcome against recent runs, and a long run sends a notification.
- **Test results Claude can act on.** A 959-test run's result shrinks from about 122,000 characters to about 1,000: the failures, each with its `file:line`; a crash's exception and top frames; why each test was skipped; the expected failures the counts leave out; and a warning when a filter matched no tests. A compile error is counted once.
- **The last failures in a pane.** `/xcrew failures` lists every failing test and compile error of the last failing run, beside the chat.
- **A guard for generated projects.** In a Tuist or XcodeGen project, the Xcode MCP's `XcodeWrite` re-saves the whole generated `.pbxproj`; Xcrew refuses it there and points Claude at its own Write tool.
- **Setup and doctor.** `/xcrew:setup` writes MobileBuildMCP's per-project profiles from your schemes and installed simulators. `xcrew doctor` checks the Mac and the project, prints the fix for anything wrong, and says when a newer Xcrew is out.

## Quick start

You need macOS 26 or later, Xcode 27 or later, [Homebrew](https://brew.sh) and [Claude Code](https://claude.com/claude-code).

**As a Claude Code plugin**, in a terminal, from your project:

```sh
claude plugin marketplace add breferrari/xcrew
claude plugin install xcrew@breferrari --scope project   # or --scope local: this project, only you
```

Install it per project, not for your whole user: its servers and tools are only useful in Apple-platform projects, and at user scope they'd start in every session.

Then once per Mac, in a terminal:

```sh
brew install getsentry/xcodebuildmcp/mobilebuildmcp
sudo xcrun mcp-server enable
```

Restart Claude Code in your project and run `/xcrew:setup`. The first call builds Xcrew's small Swift CLI, about ten seconds, once per version.

**With [mcs](https://github.com/mcs-cli/mcs)**, which installs the Homebrew package and the plugin together and asks the setup questions:

```sh
mcs pack add breferrari/xcrew
mcs sync
```

Either way, the last step is approving Claude Code in Xcode's dialog the first time Claude calls the Xcode MCP. `xcrew doctor` tells you when anything is still missing:

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

## What you get

| Piece | What it does |
| --- | --- |
| MCP servers | MobileBuildMCP (started in your project, telemetry off), the Xcode MCP (`xcrun mcpbridge`), Sosumi |
| Session briefing | The routing rules in [`context/routing.md`](context/routing.md), plus what this project or Mac still lacks; silent outside Apple-platform projects |
| Mod | The live line above the prompt, compact test and build results, the failures pane, the `XcodeWrite` guard and a note in its description (in generated projects), the `/xcrew` command |
| Skills | `/xcrew:setup`, and `xcrew:reference`, which Claude loads when something fails (it isn't in the `/` menu) |
| CLI | `xcrew setup`, `doctor`, `xcode-skills`; on Claude's `PATH` while the plugin is enabled |

While a build or test runs, a coloured line above the prompt counts it and names the scheme and simulator it's using. When it ends, the same line says how it went, how it compares with recent runs of the same tool, and what failed. Where that line can't draw, such as VS Code, the status line counts and a toast reports the outcome:

<img src="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/band.png" alt="The line above Claude Code's prompt: a test run with its elapsed time, a gauge and the phase; then a passing run, a failing run and a failed build, each against its usual time" width="100%">

What Claude reads from a MobileBuildMCP test run is the short version. A failing run keeps its failures and skipped tests and leaves the passing ones out. The location of each failure, a crash's frames and each skip's reason come from the run's result bundle, since xcodebuild logs none of them for tests on parallel simulators. A passing run's per-test list stays in the file Claude Code saved, a read away:

<img src="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/test-result.png" alt="What Claude reads from a failing test run: two failures, one with its file and line, one a crash with its exception and top frames; a skipped test with its reason; and the summary" width="100%">

A run that takes a minute or more also sends its outcome as a notification, through your own Claude Code notification settings.

`/xcrew doctor`, `/xcrew history` (each tool's usual duration, per scheme and test selection), `/xcrew failures` (a pane listing every failure of the last failing run; `/xcrew close` closes it) answer at once, without a turn for Claude. When a session starts with something wrong, such as Claude Code not yet approved in Xcode, the band says so until the first run.

<img src="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/failures-pane.png" alt="The failures pane beside the chat, listing each failing test with its file, line and message" width="100%">

`xcrew xcode-skills` copies the agent skills your Xcode ships (SwiftUI, accessibility, device interaction) into the project. It copies whatever the installed Xcode has, so run it again after an Xcode update to pick up new ones.

## Which server does what

The short version Claude gets at session start:

| Job | Server | Why |
| --- | --- | --- |
| Build, test, coverage, simulators, UI automation, LLDB | MobileBuildMCP | Runs `xcodebuild` with its own DerivedData, so it never fights Xcode's; switchable profiles; test filtering |
| One file's compile errors, SwiftUI previews, code snippets, crash logs, physical devices | Xcode MCP | Uses Xcode's real build settings, which a plain language server can't read in an Xcode project |
| Apple documentation | Sosumi | Short results with each API's minimum OS version |
| Writing files | Claude's own tools | `XcodeWrite` rewrites the whole project file; refused in generated projects |

[docs/findings.md](docs/findings.md) has the evidence behind each choice, and what was tried and rejected.

## Configuration

- **Profiles.** `.mobilebuildmcp/config.yaml` holds a `unit` profile, plus `ui` and `app` when you name those schemes. Rerun `/xcrew:setup` or `xcrew setup` to change them. A config Xcrew didn't write is left alone unless you pass `--force`, which keeps a backup. The config holds this Mac's absolute paths, so setup keeps it out of git through `.git/info/exclude`, which isn't committed either.
- **Already registered the servers yourself?** Claude Code prefers your own `xcode` and `MobileBuildMCP` entries over the plugin's. Remove yours (`claude mcp remove <name>`) to use Xcrew's, or keep them: the mod works with either.

## Troubleshooting

Run `xcrew doctor` first; every line that isn't `ok` names its fix. Beyond that:

| Symptom | Cause | Fix |
| --- | --- | --- |
| Every Xcode MCP call fails with "not approved" | Xcode asks once per agent | Have Claude call `XcodeOpenWorkspace`; allow it in Xcode's dialog |
| MobileBuildMCP has only simulator tools | No `.mobilebuildmcp/config.yaml` in the project | `/xcrew:setup`, then restart Claude Code |
| `No such module 'UIKit'` from SourceKit | Claude Code's language server can't read Xcode projects | Ignore it; the Xcode MCP's diagnostics are the real ones |
| A build fails with "produced malformed response" | Usually a macro plugin macOS killed: Tuist before 4.203 generated a phase that overwrites plugins in place, and `xcrew doctor` names the projects that have it. Otherwise a toolchain mismatch or stale prebuilt macros | Upgrade Tuist to 4.203 or later and regenerate; until then, clean the build folder and rebuild. Check `xcode-select -p` points at the Xcode you build with |
| A session starts with an `xcrew: building the CLI` error | The Swift toolchain is older than 6.2, or Xcode's command-line tools aren't selected | `xcode-select -p` should point into Xcode 27; `sudo xcode-select -s /Applications/Xcode.app` |
| `project-config` warns the config points at a missing workspace | The project moved or the workspace was renamed | `/xcrew:setup` |

## Updating and removing

- **Update:** Claude Code doesn't update plugins from a marketplace like this one until you turn it on: `/plugin` → **Marketplaces** → `breferrari` → **Enable auto-update**, and new releases install in the background. Otherwise, `claude plugin marketplace update breferrari && claude plugin update xcrew@breferrari`, or `mcs sync` with mcs. `xcrew doctor` says when a newer release is out. The CLI rebuilds once for the new version and removes the old build.
- **Remove:** `/plugin uninstall xcrew@breferrari` (or remove the pack with mcs), then, if you like, `rm -rf .mobilebuildmcp` in each project (and its `/.mobilebuildmcp/` line in `.git/info/exclude`), `rm -rf ~/Library/Caches/xcrew`, and `brew uninstall mobilebuildmcp`. To revoke Claude Code's access to Xcode, find its id in `xcrun mcp-server status` and run `sudo xcrun mcp-server deny <id>`; `sudo xcrun mcp-server disable` turns headless mode off.

## How it works

<img src="https://raw.githubusercontent.com/breferrari/xcrew/main/assets/architecture.png" alt="Claude Code loads the plugin's four pieces: .mcp.json starts the three MCP servers; the session hook, the mod and the skills call the Swift CLI, which the mcs techpack calls too" width="100%">

All logic lives in one dependency-free Swift package. The plugin, the hooks, the mod and mcs call that CLI, so there is one implementation, and `Tests/ManifestTests` fails when an install path drifts from it. [docs/architecture.md](docs/architecture.md) walks through the layout.

## Development

```sh
swift test                     # CLI, core, shim and manifest-parity tests
claude plugin test .           # the mod's tests, against Claude Code's own engine
claude plugin validate .
mcs pack validate .            # when mcs is installed
claude --plugin-dir .          # try your checkout in a session
```

[CONTRIBUTING.md](CONTRIBUTING.md) covers the conventions, and how to add a check, a command or a mod behaviour.

## What it runs and reaches

- **On your Mac.** The first session builds Xcrew's command-line tool from this repository's Swift source with `swift build`, into `~/Library/Caches/xcrew`. The plugin starts three MCP servers: Apple's `xcrun mcpbridge`, the Homebrew `mobilebuildmcp`, and Sosumi over HTTPS. The mod reads MobileBuildMCP's run logs and runs `xcrun xcresulttool` on a failing or skipped test run's result bundle. Nothing runs with `sudo`: the one `sudo` command, enabling Xcode's MCP server, is yours to run in *Quick start*.
- **Over the network.** Xcrew has no telemetry, and it turns MobileBuildMCP's off. Its one request is `xcrew doctor`'s check for a newer release: a GET to GitHub's API for this repository's latest release, which the session-start check leaves out. Sosumi is a third-party documentation service that receives your documentation searches; see [sosumi.ai](https://sosumi.ai).

## License

[MIT](LICENSE).
