# Findings

What Xcrew's choices rest on. Measured in October 2026 on one Mac (macOS 26, Xcode 27.1, MobileBuildMCP 2.7.1) against a large modular Tuist app; versions move, so treat numbers as that snapshot. `xcrew doctor` checks the parts that can change under you.

## The two servers

| | Xcode MCP | MobileBuildMCP |
| --- | --- | --- |
| Ships with | Xcode 27 (`xcrun mcpbridge`) | Homebrew, from Sentry (formerly XcodeBuildMCP) |
| Builds through | Xcode itself, in Xcode's DerivedData | `xcodebuild`, in its own DerivedData |
| Knows | The open project: navigator, active scheme, real build settings | Whatever you point it at, through session-default profiles |
| Unique strengths | Per-file diagnostics, SwiftUI previews with variants, code snippets in a module, Organizer crash and performance logs, string catalogs, physical devices | Test filtering, coverage reports, simulator control and environment, UI automation by accessibility tree, LLDB |
| Settings | None of its own; Xcode decides | `.mobilebuildmcp/config.yaml`: tool groups, profiles, debugger backend |

They overlap on build, test and run. Xcrew sends those to MobileBuildMCP because its DerivedData never collides with Xcode's, its profiles survive restarts, and it filters tests. The Xcode MCP keeps what only it can do.

## Behaviours that shaped xcrew

- **The Xcode MCP works with Xcode closed.** After `sudo xcrun mcp-server enable`, the server runs headless. Each agent is approved once, through a dialog Xcode raises on that agent's first call; `xcrun mcp-server status` lists approved agents.
- **The Xcode MCP's file tools take project-navigator paths, not disk paths.** A disk path fails with "File not found in project structure".
- **`XcodeWrite` re-saves the whole project file.** Creating one file rewrote over a thousand lines of a generated `.pbxproj` in Xcode's newer format. Projects with synchronized folders, and generated projects, pick up files written to disk anyway, so the guard costs nothing.
- **Previews, snippets and diagnostics follow the active scheme.** "Active scheme does not build this file" means switching scheme, which also changes the person's Xcode window.
- **Macro plugins die after an in-place rewrite.** The kernel caches a Mach-O file's code signature and doesn't flush that cache when the file is rewritten in place, so the next launch is killed; Apple's guidance is to replace such a file rather than overwrite it ([Apple Developer Forums](https://developer.apple.com/forums/thread/130313)). **The trigger is the macro copy phase older Tuist versions generate.** Up to Tuist 4.202, for each macro target, Tuist generates a Run Script phase that copies the macOS-built plugin into the products folder of a non-macOS destination (`Debug-iphonesimulator/`) with `cp -f`, which writes into the existing file and keeps its inode. Reproduced directly: with a copy of a plugin running, as the compiler and the indexer keep them, `cp -f`-ing a new build over it makes every later launch of that path exit with SIGKILL, while a copy-and-rename over it runs again. Seen with Tuist 4.202.8. Tuist 4.203.0 removed the phase ([tuist#11825](https://github.com/tuist/tuist/pull/11825): "the macro executable copy build phase has been removed"), so projects generated with 4.203 or later don't have this trigger; upgrading Tuist and regenerating is the fix. It hits the regular build and the indexer's (`Index.noindex/Build/Products`) alike; a dead indexer copy breaks macro expansion in the editor without any failing build. Xcode's own linking doesn't trigger it: a plain Swift macro package rebuilt three times in Xcode 27.1 got a new inode each time and never died. The build reports "produced malformed response". Copying the bytes beside the plugin and renaming the copy over it revives it, and Xcrew did that automatically up to 0.6.10. It dropped the repair in 0.7.0: finding a dead plugin meant launching every plugin in DerivedData to probe it, and Tuist 4.203 removed the cause. `xcrew doctor` still names projects generated with the old phase. The same message also comes from other causes, such as a toolchain mismatch or stale prebuilt macros.
- **SourceKit can't read Xcode projects.** Claude Code's Swift language server reads settings only from a Swift package, a compilation database or a build server. Without a `Package.swift` it checks each file alone against the macOS SDK, so `import UIKit` and every first-party module show as errors. The Xcode MCP's `XcodeRefreshCodeIssuesInFile` uses the real settings.
- **The XcodeBuildMCP → MobileBuildMCP rename (2.7.1) has no fallback.** The binary, the `MOBILEBUILDMCP_*` variables and the config folder (`.mobilebuildmcp/`) all changed; an old `.xcodebuildmcp/config.yaml` is ignored silently, leaving only the simulator tools. An old binary on `PATH`, from Homebrew or npm, can shadow the new one.
- **MobileBuildMCP reads its config from its working directory**, so the plugin starts it in the project root.
- **MobileBuildMCP's test list can leave out a skipped test.** In a run that also crashed and recorded an expected failure, its text counted `1 skipped` but listed no `⏭️` line for it, though xcodebuild's log and the result bundle both had it. So Xcrew reads skipped tests and their reasons from the result bundle's test list (`xcresulttool get test-results tests`), not from that text. A dropped passing test is reported as getsentry/MobileBuildMCP#563.
- **`test_sim` takes no scheme argument**; the scheme comes from the session defaults, and `-only-testing:` goes in `extraArgs`.
- **MobileBuildMCP's command line resolves simulator names on the newest installed iOS only**; the MCP server doesn't have this limit.
- **LLDB `expr` needs `debuggerBackend: lldb-cli`**; the default backend handles attach, stacks and breakpoints.
- **Coverage tools need an absolute `.xcresult` path**; `~` isn't expanded.
- **The `mobilebuildmcp://doctor` resource reports Sentry as enabled regardless.** That line reads only a legacy variable; the environment section below it is accurate.
- **Sosumi beats `DocumentationSearch` for documentation**: short results with links, WWDC sessions, and each API's minimum OS version. `DocumentationSearch` matches the installed SDK and works offline.
- **`IDEAllowUnauthenticatedAgents`** lets any unsigned process drive Xcode's tools; leave it off. Turning it off doesn't cut Claude Code off: on October 29, 2026 (Xcode 27.2 beta 3, 27B5038j; macOS 27.0; Claude Code 2.1.312; MobileBuildMCP 2.7.1), setting it to `NO` and restarting Xcode left every doctor check `ok`, `xcode-mcp/claude-approved` included. That check reads a status, so a working Xcode MCP call is the stronger proof. On that Mac the value was already `1` before Xcrew first ran, so something else set it; Xcode itself is the likely source (unverified).

## Build and test progress

Measured October 2026 (Xcode 27.1, MobileBuildMCP 2.7.1, Claude Code 2.1.312). The band's gauge is time against the usual duration because no exact count reaches a mod:

| Layer | Exact progress? | What it carries |
| --- | --- | --- |
| Apple's build system (swift-build) | Yes | `BUILD_PROGRESS_UPDATED` messages with `percentComplete` and a status line (`Sources/SWBProtocol/BuildOperationMessages.swift`). Xcode draws its progress from them |
| Xcode MCP | Yes | MCP progress notifications (`Building • 836 / 850`), which Claude Code draws under the tool call |
| xcodebuild's output, as MobileBuildMCP logs it | No | Task lines naming their module, written as the run goes; one total near the start, `Target dependency graph (35 targets)`. Test results arrive in a few batches as the parallel runners flush |
| xcodebuild's result stream (`-resultStreamPath`) | No | Task start and end events only: a sample package's build gave 160 of each, no percentage or total |
| MobileBuildMCP | No | Its parser reports stages (compiling, linking, testing) and counts tests before a run from the test sources, but only its command-line tool receives them; the MCP server sends no progress |
| Claude Code's mod API | No | The `ToolProgress` render site carries only the run-in-background hint, and `$.mcp.call` returns only a result |

Counting modules from the log was tried and dropped: xcodebuild starts work on nearly every module early (33 of 35 had a task a quarter of the way into a clean build) and prints no line when one finishes, so the count sat near its total for most of the build.

## MobileBuildMCP's upkeep

Measured 2026-10-28. MobileBuildMCP is most of what Xcrew sets up, so how it's kept up decides how much Xcrew can lean on it.

| Since July 2026 | |
| --- | --- |
| Commits a month | 70–77 in March and April; 47, 11, 27, 3, 8 from May to September; 2 in October so far |
| Releases | 2.7.0 (July 23) and 2.7.1 (September 23), after one or two a month before |
| Issues opened | 42: 20 open, 15 closed as not planned, 7 completed; 19 of the last 23 closures were by a bot |
| Pull requests | 25 merged, 24 closed unmerged, 13 open; 14 of the merged ones are by one maintainer |

Sentry acquired the project in February 2026, and activity peaked in the two months after; the slowdown began around June. Xcrew's two reports, getsentry/MobileBuildMCP#563 and #564, are open.

What follows from it now: Xcrew works around MobileBuildMCP's problems in the mod and the CLI (compacting results, reading counts from the summary) rather than waiting on fixes, and keeps the Xcode MCP as the second server.

If upkeep keeps falling, the options, cheapest first:

1. **Lean on the Xcode MCP** for builds and tests, with MobileBuildMCP kept for what only it does (simulator control, UI automation, LLDB).
2. **Fork MobileBuildMCP** (MIT) and carry the fixes Xcrew needs. Cost: keeping up with Xcode and simulator changes ourselves.
3. **A server of Xcrew's own**, in Swift beside the CLI, covering only build, test and run on a simulator, with results shaped for an agent from the start. Cost: the largest, and it duplicates a working tool.

When to revisit: a new Xcode or iOS release that MobileBuildMCP hasn't followed within a few weeks, a bug that blocks builds or tests with no fix upstream, or #563 and #564 closed unanswered.

## Test reports from the two servers

Measured 2026-10-28 on a modular app's 961-test target (959 passing, 2 expected failures), with one assertion failure, one thrown error, one crash and one skipped test added on purpose, run on parallel simulator clones.

| | MobileBuildMCP alone | Xcode MCP (`RunAllTests`) | MobileBuildMCP with Xcrew |
| --- | --- | --- | --- |
| A failing run's result | Text listing every test, ~80 K characters, cut by Claude Code | JSON, ~20 K characters: up to 100 results, the rest in a file | ~1 K characters: failures, skipped tests, the summary |
| A passing run's result | JSON, ~122 K characters, saved to a file and read back with `jq` | JSON | ~1 K characters, the per-test list pointed to |
| Failure location | None (xcodebuild logs none for tests on parallel clones) | `file:line` as a project-navigator path | The file's absolute path and line, from the result bundle |
| Crash | Test and closure | "Test crashed with signal trap" | Test and closure, the exception, the crashed thread's top frames |
| Skipped test | Counted | Named | Named, with its reason |
| Expected failures | Left out of the counts | Counted | Named in a note with the true total |
| A filter matching nothing | `SUCCEEDED` with 0/0/0 | An explicit error | `SUCCEEDED`, flagged in the band and in a note to Claude |

As runners they differ the other way. MobileBuildMCP runs `xcodebuild` on its own, so it leaves the person's Xcode window, its scheme and its DerivedData alone; pins the simulator its profiles name; takes any `-only-testing` or `-skip-testing` filter; and adds coverage, simulator control, UI automation and LLDB. The Xcode MCP switches the IDE's active scheme to run, uses the scheme's own destination, and has no coverage. So Xcrew keeps MobileBuildMCP for builds and tests and makes its reports the smallest of the three, and the Xcode MCP stays the fallback runner in *MobileBuildMCP's upkeep* above, at the cost of those runner features.

A passing run's result reaches Xcrew only through the notice Claude Code puts in its place. The [MCP docs](https://code.claude.com/docs/en/mcp#mcp-output-limits-and-warnings) say only that it "replaces it in the conversation with a message that names the file path", and that "the file goes in the session's `tool-results` directory". So `Report.savedPath` finds the file by that path, an existing file in a `tool-results` folder named in a short text, and not by the wording. The docs put the saving point at 50,000 characters for a text result (October 2026); `Report.noticeLimit` reads a text as a notice up to 10,000, a margin for the saved JSON's schema the notice names. On October 29, 2026, Claude Code 2.1.312's executable carried one template for it, as source text: `Error: result (… characters) exceeds maximum allowed tokens. Output has been saved to ${path}.` followed by a newline and `Format: ${format}`. The weekly canary fills in that template from the newest Claude Code and checks that `xcrew report` still reads the saved result back (`scripts/saved-notice.sh`). A new wording, or a template the executable no longer carries as text, opens an issue.

## How Foundation sees a project's folders

Where Apple's docs are silent, the project search rests on these probes, taken on October 29, 2026 on macOS 27.0.1 with APFS, case-insensitive. Each is pinned by a test in `Tests/XcrewCoreTests/ProjectTests.swift`, so a platform change shows up red.

| Question | Docs | What came back |
| --- | --- | --- |
| Does listing a folder by URL follow a symlink to it? | `contentsOfDirectory(at:…)`: "does not traverse symbolic links" | It throws for a URL that is a symlink to a folder; `contentsOfDirectory(atPath:)` follows it. The search starts from the resolved root |
| Does `resolvingSymlinksInPath()` resolve the `/System/Volumes/Data` firmlink and letter case? | Silent beyond symlinks | Yes: a symlink to the home folder, `/System/Volumes/Data/Users/x` and `/USERS/X` all became `/Users/x`. `canonicalPathKey` alone leaves a final symlink unresolved |
| Is the volume case-insensitive? | `volumeSupportsCaseSensitiveNamesKey` | `false` here. Manifest names match without regard to case only where the volume says so |
| What is standard input: a file, a pipe or a device? | Silent | `FileManager.attributesOfItem(atPath: "/dev/fd/0")` reports `NSFileTypeRegular` for a file, `NSFileTypeUnknown` for a pipe and `NSFileTypeCharacterSpecial` for `/dev/null`; `/dev/stdin` itself reads as a symbolic link. A file is read to its end at once, since waiting on it for more input never ends |
| Which folders are packages? | `isPackageKey`: a package by its extension or by its own flag | True for `.xcodeproj`, `.xcworkspace`, `.app`, `.bundle`, `.playground`, `.xcdatamodeld`; false for `.xcassets`, `.framework`, `.xcframework`, `.lproj`, `.docc`, `.xctestplan` and dotted folders such as `MyApp.iOS`. The search skips a package or an `.xc…` folder, and enters the rest |

## The simulator setup picks

The session briefing names the simulators booted now. `simctl help list` documents the `booted` search term as "a simple case-insensitive contains check against the item's description", so a shut-down device whose name holds the word is listed too, and the briefing reads each device's `state`. On October 29, 2026 (macOS 27.0.1, Xcode 27.2 beta 3, CoreSimulator already running), `xcrun simctl list devices booted -j` took 0.12 to 0.14 s over six runs, and the session-start hook went from 0.02 s to 0.17 to 0.19 s with the service check below. A cold CoreSimulator wasn't measured, so the briefing waits one second for `simctl`, plus up to the runner's one-second grace to stop it, and leaves the line out after that. It asks only while `com.apple.CoreSimulator.CoreSimulatorService` runs (`pgrep -x`, about 0.02 s): no simulator is booted without it, and `xcrun` would start it, or on a Mac without the developer tools offer to install them.

With Xcode 27.2 beta 3 on October 29, 2026, the iPhone Duo came on a runtime of its own. `simctl list runtimes` names it `com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4` and gives its `version` as 27.2, the same as the plain `iOS-27-2` runtime. Read from the identifier, it looked newer than 27.2, so setup picked the Duo. Setup now takes each runtime's version from `simctl list runtimes`, and falls back to the identifier's leading numbers only.

The Duo has two displays, and MobileBuildMCP 2.7.1's `screenshot` takes no display, so it fails there. `simctl` documents no display count. The device type's CoreSimulator profile, at its `bundlePath` from `simctl list devicetypes` plus `Contents/Resources/capabilities.plist`, lists its displays, and the built-in ones are powered on by default (`powerState` 1). That's `LCD` and `LCD-1` on the Duo, and `LCD` alone on the iPhone 17; `TVOut`, `Wireless` and `Resizable` are off. Setup never defaults to a device type with more than one, and the doctor warns about a configured one. The `displays` list is new with Xcode 27: on CI's `macos-26` runner (Xcode 26.x, the same day) a plain iPhone's profile had none, `plutil -extract` printed nothing, and no device type counts as two-display there, which is right, since those Xcodes ship no such device. A display without `powerState` counts as off, so the check fails open: a profile that drops the key would let a two-display device through. A test reads a plain iPhone's installed profile wherever it lists displays, so a change to that shape turns it red.

## How mcs marks a project

mcs records each project it set up in `<project>/.claude/.mcs-project`, a JSON file that `mcs sync` writes, with the packs it configured under `configuredPacks` (mcs's `docs/architecture.md`, *Project State*, and `Sources/mcs/Core/ProjectState.swift`, read on October 29, 2026). A fix text names mcs only when that list holds `xcrew`, the techpack's identifier.

## How the plugin directory reads a plugin

From the directory's validation of `main` at two commits on October 29, 2026, beyond what its checklist states. Each is pinned by a test in `Tests/ManifestTests`.

| Observation | What changed |
| --- | --- |
| It resolves a name in the hooks module without regard to scope: a top-level helper that takes `$`, named like a variable inside a hook, reads as `$` passed to that hook's own binding. Claude Code's local `claude plugin validate` reads the same file correctly | The helper and the hook's variable have different names, and a test fails when a helper that takes `$` shares its name with another binding |
| It reads an MCP server's command only when it's a file of the plugin with plain arguments: `xcrun` with `mcpbridge`, and `/bin/sh -c`, were each held as a command it couldn't read | Both local servers start from scripts in `libexec/` |
| It holds a bundled image the README shows with an HTML `<img>` tag; its checklist asks for Markdown's image syntax | The README's images are Markdown, and a test fails on an `<img>` tag |
| Its listing preview shows the README away from the repository: an image at a relative `assets/` path appeared as its alt text | The README's images are absolute `raw.githubusercontent.com` URLs to this repository's `assets/`, and a test fails on any other image source |
| Without `documentationUrl`, the listing took the README's first link, Sosumi's site, as the plugin's documentation | `plugin.json` sets `documentationUrl` and `supportUrl`, and a test fails on a field the manifest reference doesn't document |

## How a marketplace install picks its code

On October 29, 2026 (Claude Code 2.1.312), a fresh install from the marketplace recorded `version` `0.8.1` and `gitCommitSha` `5b646cc` in `installed_plugins.json`. That commit was five past the `v0.8.1` tag. With `"source": "./"`, the plugin came from the marketplace's own clone of the default branch, and [Host and maintain a marketplace](https://code.claude.com/docs/en/plugins/host-marketplace.md) says updates follow `version` alone: "Users get a new copy only when the plugin's computed version differs from the one they have." So two `0.8.1` installs could run different code.

The entry now names the release tag (`"ref": "v<version>"` on a `github` source), which the same page documents: "`ref` names a branch or tag and `sha` names a commit for a `github`, `url`, or `git-subdir` source." Only the plugin's code follows the ref. The catalog, `marketplace.json`, is still read from the default branch, since only "`#<ref>` on the add command" changes that, so `claude plugin marketplace add breferrari/xcrew` works as before.

The ref moves in a pull request of its own, after the tag is pushed and the release workflow has published it. If the release pull request moved it instead, the catalog would name a tag that doesn't exist yet from the merge until the push, and installs would fail meanwhile. It would also still name the tag if the workflow refused it. Pinning a `sha` doesn't help either, since the squash merge makes the release commit and its hash isn't known before. A release branch added with `#release` would avoid the gap, but every existing user would have to add the marketplace again. So a test allows the ref to be this version or the previous release, and only a version the changelog has released. Since October 29, 2026, the entry names the `stable` branch instead, which the release workflow moves; see *Installs that follow a branch* below.

The first release through this flow, 0.8.2 on October 29, 2026, was checked without touching anyone's install: `CLAUDE_CONFIG_DIR=$(mktemp -d) claude plugin marketplace add breferrari/xcrew`, then `claude plugin install xcrew@breferrari --scope user` with the same variable. The temporary `plugins/installed_plugins.json` recorded `version` `0.8.2` and `gitCommitSha` `1273068`, the tag's commit, while `main` had moved on to the install pull request (`da128b3`).

## MobileBuildMCP's profiles

MobileBuildMCP 2.7.1 documents none of this, upstream or in its Homebrew install, so it comes from its source (`build/` in the install), read on October 29, 2026:

- **A named profile stands alone.** `session-store.js` reads a profile as `profiles[name] ?? {}`, with nothing from the global `sessionDefaults`. So an active profile without a scheme can't build or test, whether it's empty or absent.
- **`simulatorId` is filled at startup, for the active profile only.** `bootstrap-runtime.js` resolves the active profile's `simulatorName` to an ID. `session_use_defaults_profile` never does, so after a switch, tools that need an ID, such as `screenshot`, fail with `simulatorId is required`. Setup writes each profile's ID itself, from `simctl`.
- **`session_set_defaults` with a `simulatorId` clears `simulatorName`**, and **`screenshot` takes no display parameter**, so it fails on a simulator with two displays. Both were seen with Xcode 27.2 beta 3.

`mobilebuildmcp --version` takes about 0.5 s, most of what `xcrew doctor --problems` costs (0.51 to 0.56 s in a one-project tree on October 29, 2026, M1 Max, macOS 27.0.1). The band asks the doctor again after prompts, so the CLI keeps the answer in its cache folder, keyed by the binary's resolved path and modification time. Homebrew links the command into a folder named for the version, so an upgrade changes the key.

MobileBuildMCP 2.7.1 reads its config once, when its server starts, and doesn't watch it: its only file watcher, `utils/xcode-state-watcher.js`, follows Xcode's `xcuserstate` for the scheme and simulator. So a config changed after the server started needs a restart. It also writes the config itself: `session_set_defaults` and `session_use_defaults_profile` with `persist: true` go through `persistProjectConfigPatch` in `utils/project-config.js`. So the file's own time can't say whether the server has what's in it. The check compares the time xcrew last wrote it, from `.xcrew-managed`, which setup leaves alone when the content is the same. That covers setup, and `mcs sync` through setup. It started out meant to catch every writer, and a hand edit is the one it can't tell from the server's own writes, so that needs a restart by hand. On macOS 27.0.1 on October 29, 2026, the doctor told which server is this session's like this:

- **The server is one process.** The Homebrew launcher execs `node-runtime …/libexec/build/cli.js mcp`, so `ps -axo pid=,ppid=,etime=,command=` shows it as that command.
- **Its folder is the project root.** `lsof -a -p <pid> -d cwd -Fn` prints it on an `n` line, and the plugin's server script starts it there.
- **Its age reads the same in any locale.** `etime` is `[[dd-]hh:]mm:ss`, unlike `lstart`, so its start is now minus `etime`.
- **This session's server shares the doctor's Claude Code process.** Walking the `ppid` chain from the doctor reaches the first process whose program is `claude`, by `ps`'s `comm`, since the desktop app's path has a space a command line can't be split at. The server it started is beneath it. A server started from a shell and backgrounded is reparented to `launchd`, so it's no session's. From a terminal there's no `claude` above the doctor, so the oldest server for the project under any Claude Code stands for a stale one. A server whose Claude Code exited is no session's, and doesn't count.

Setup reads the unit-test scheme from the project instead of asking. Apple documents schemes in Xcode's interface, not the `.xcscheme` file, so the reading follows the files Xcode 27.2 beta 3 writes:

- A scheme's `TestAction` lists `TestableReference`s, each naming its target as `BuildableReference`'s `BlueprintName` and marked `skipped = "YES"` when it doesn't run. It can also name test plans (`TestPlanReference reference = "container:…"`), whose JSON lists `testTargets[].target.name`.
- Only shared schemes (`xcshareddata`) count. Schemes under `xcuserdata` are one person's and aren't committed. A workspace lists its projects in nested `Group`s, each `group:` path relative to the group around it, and a testable's `ReferencedContainer` says which project holds its target, since two projects can each have one called `Tests`.
- Unit and UI test bundles are both `.xctest`, so the target's product type decides: `com.apple.product-type.bundle.unit-test` in `project.pbxproj`, or `product-type: bundle.unit-test` in the JSON `project.xcproj` that Xcode 27.2 writes by default. The JSON keys come from the format's source (apple/xcode-project-format 0.1.0), not from a file Xcode wrote here. Projects with buildable folders still declare their targets in either file. When neither file names a scheme's target, setup says it couldn't tell and lists the schemes instead of guessing.

## Making the test bed's projects

Xcode 27.2's `xcodeproj` tool (`xcrun xcodeproj`) makes the JSON form. Its own help says `init` writes `project.xcproj`, the JSON format, and that it never writes schemes or workspaces; nothing in it converts between formats. Its help doesn't say what `group include` does for a target without build phases. On October 29, 2026 (Xcode 27.2 beta 3), including a synchronized folder in such a target recorded every file in it as a membership exception, so nothing compiled and the app came out without an executable. Adding the Sources, Frameworks and Resources phases first left no exceptions, and the app built. The test bed's `scripts/generate.sh` adds them first, and `TestbedTests` checks that no JSON form carries an exception. XcodeGen 2.46.0 makes the buildable-folders form natively (`syncedFolder`, "Xcode 16's synchronized folders, also known as buildable folders"). Tuist 4.214.0 writes a "Generate Project" scheme holding the absolute path it ran in, which the script removes. In that format a Run Script phase's script is a list of lines (`"kind": "script"`, `"script": [...]`), so the comment the macro copy phase check looks for stays on one line. Apple's "Updating your Xcode project configuration file format" says a project made with an earlier Xcode can switch to the JSON format, and the switch replaces `project.pbxproj` with `project.xcproj`. So a project Tuist generated before 4.203 can carry the old phase in either file, and xcrew reads whichever one a bundle holds.

## What an install copies

A marketplace install copies the plugin's whole folder, which for xcrew is the repository. The plugin docs offer no ignore file and no include or exclude list ("Create a marketplace", "Plugin sources", read October 29, 2026). The one way to narrow a copy is the plugin's `source`: a relative path or a `git-subdir` copies only that folder. That is why the test bed lives in its own repository, [xcrew-testbed](https://github.com/breferrari/xcrew-testbed). It is also how the README's images could leave installs, if they ever need to.

## Installs that follow a branch

The marketplace reference says a git source's `ref` is "a branch or tag", and the plugin loading reference says an installed plugin's version comes from "the `version` field in the plugin's manifest" first, which `claude plugin update` compares to decide whether to update. On October 29, 2026 (Claude Code 2.1.312), with a throwaway `CLAUDE_CONFIG_DIR`, a local marketplace and a plugin served from a local bare repository by `url` source with `"ref": "stable"`: the install took 1.0.0; moving `stable` to a commit declaring 1.0.1 and running `claude plugin update` updated it to 1.0.1; moving `stable` again without changing the version left it "already at the latest version (1.0.1)". So installs follow `stable` from one release to the next and never between them. The weekly canary repeats this against the newest Claude Code (`scripts/stable-follows.sh`).

## Which log is the run's

While a MobileBuildMCP build or test runs, the band reads its log. MobileBuildMCP 2.7.1's source, read on October 29, 2026 from its Homebrew install's `build/`, says where that log is. `utils/workspace-identity.js` names a project's workspace folder with `workspaceKeyForRoot`: the root's folder name with every run of characters other than letters, digits, `.`, `_` and `-` made one `-`, then a `-`, then the first 12 hex digits of the SHA-256 of the root path. The root is the folder above `.mobilebuildmcp/` when a config was found, else the real path of the server's working folder. `utils/xcodebuild-log-capture.js` names each log `<tool>_<timestamp>_pid<server pid>_<suffix>.log`. Matching workspace folders by name prefix let two checkouts of folders with one name, and two sessions in one checkout, read each other's logs. Foundation's `resolvingSymlinksInPath()` drops a leading `/private` (`/private/var/…` comes back as `/var/…`), while Node's `realpath`, which MobileBuildMCP uses, keeps it; `canonicalPathKey` matches Node. A test whose expected key came from the code's own path call couldn't see the difference; one whose expected key comes from `/bin/realpath` and `shasum` did. So `RunLog` computes the exact key, under both the root as given and its real path, and keeps only the logs of the MobileBuildMCP servers under this session's Claude Code. A test runs the installed `workspaceKeyForRoot` with the Node runtime MobileBuildMCP ships, wherever it's installed (this Mac, the weekly canary), so a change upstream shows up red.

## Where the plugin declares its servers

The plugin's root is the repository's, so a `.mcp.json` there is two things at once: the plugin's server config, and the project's own `.mcp.json` for any session opened in the repository. On October 29, 2026 (Claude Code 2.1.312), `claude mcp list` with a throwaway config in a folder holding that file reported "Missing environment variables: CLAUDE_PLUGIN_ROOT", since nothing sets it outside a plugin. Sessions in the repository then started MobileBuildMCP and the Xcode MCP at `/libexec/...` and failed with ENOENT. The manifest reference documents `mcpServers` in `plugin.json` as "loaded together with `.mcp.json`", and says `claude plugin validate` checks servers declared "in `.mcp.json`, in a `.json` file that `mcpServers` names, or inline in `plugin.json`". So the servers now live inline in `plugin.json`. Installed from a branch with a throwaway config, all three reported "✔ Connected". The directory's pre-submission checklist states its server-command rules for "each MCP server" without naming a file, and names `.mcp.json` only for its JSON check. It doesn't say outright that the scan reads `plugin.json` the same way, so the next portal validation confirms it.

## MobileBuildMCP's CLI and its MCP results

Recordings of real runs have to be the results Claude reads, which come through MCP. MobileBuildMCP's CLI runs the same tools, and its documentation (xcodebuildmcp.com, *Output Formats* and *CLI*, read October 29, 2026) says it "exposes the same tool results through the CLI and MCP server", but presents them differently. In CLI output, next steps "render as shell commands; in MCP output they render as MCP tool-call hints". `--style minimal` gives only "compact MCP-like" text. CLI text lists file artifacts as rows where "MCP text defaults to `tree`". `--output json --style minimal` "keeps the structured-output envelope but omits request/frontmatter fields", and nothing says it equals the MCP `structuredContent`. So the test bed records nothing through the CLI: its recordings come from a session where the servers connect.

## When a generated project is stale

After Claude edits a manifest, the generated project changes only when the generator runs again. File times can't say whether that happened. On October 29, 2026, with Tuist 4.214.0 on the test bed's Tuist fixture, `tuist generate` kept the workspace's and `project.pbxproj`'s modification times in two cases:
- after `touch Project.swift`;
- after an edit that produced the same project.

Tuist writes only files whose content changes. Comparing a manifest's time with the project's would therefore read "stale" forever after a generate that changed nothing. So the mod marks the project from what it sees this session: an edit to a manifest marks it, and a `tuist generate` or `xcodegen generate` that succeeds clears the mark. A test runs a generate on a copy of the fixture wherever Tuist is installed, so a Tuist that starts rewriting unchanged files shows up red.

The mod can tell a failed generate only by the Bash result's `isError`. The engine's types say it's set when the tool "reported an error", without naming an exit status. In this repository's session transcripts (Claude Code 2.1.312, October 29, 2026), every Bash command that exited non-zero is stored as an error result whose text starts `Exit code 1`. The mod's tests stand on that. A shell reports a pipe's or a list's last command, so a generate piped into `tail` or followed by `; echo` would look like a success even when it failed. Such a command clears nothing, and the build is refused once more.

A person may regenerate in their own terminal, which the mod can't see. So the mark refuses one build and then lets the next one through, with a line saying why.

The stale guard holds back a run tool unless its name says it only launches. `RunProject` builds before it launches. Whether the Xcode MCP's `DeviceInteractionInstallAndRun` builds first is unverified, so it is held back by that rule too; the next session where the Xcode MCP connects confirms it from `tools/list`, with `RunSomeTests`.

## XcodeGen's included specs

XcodeGen reads every spec its spec includes, so an edit to one marks the project stale like an edit to `project.yml`. Read on October 30, 2026 from XcodeGen's `Docs/ProjectSpec.md` and, where it is silent, `Sources/ProjectSpec/SpecFile.swift` on master:

- "Include can either be a list of includes or a single include. An include can be provided via a string (the path) or an object". The object has `path`, `relativePaths` and `enable`, both flags defaulting to true.
- "Included specs can also include other specs and so on." The loader reads each file once.
- Where an include resolves isn't in the docs. The source keeps a base folder and a relative folder for each spec and reads an include at the base joined with its path. A top-level include therefore resolves from the root spec's folder. A nested one resolves from the folder of the spec that includes it, or, with `relativePaths: false`, from that spec's base.
- An absolute include path stands alone: XcodeGen joins paths with PathKit, whose `+` returns an absolute right-hand side unchanged.
- The loader walks includes depth first, in the order written, and keeps the first spec it reads at each path. A spec reached twice therefore resolves its own includes from its first route.
- A flag is read by `resolveBoolean`: `dictionary[key] as? Bool ?? (dictionary[key] as? NSString)?.boolValue`.
  - Yams, XcodeGen's YAML library, resolves `yes`, `true` and `on`, their negatives, and each in lower, capitalized or upper case, to booleans (its `Resolver.default`, read October 30, 2026).
  - Any other text goes through `NSString.boolValue`.
  - A number resolves to neither a Bool nor a String, so the flag keeps its default, true.
- A disabled include is never read (`.filter(\.enable)` comes before the file is loaded). `${NAME}` in a spec, an include's path among them, expands from the variables the loader is given: the environment.

xcrew reads only the top-level `include` key, in those documented forms, with no YAML dependency. It resolves includes the same way. An include whose path holds a variable, or whose `enable` isn't a literal, is left out, since it depends on the environment at generate time. JSON specs are out of scope: detection doesn't find a `project.json`, and the mod doesn't ask about a JSON spec a YAML spec includes. The CLI tests pin each case. Since a spec can include another by any name, the mod asks the CLI about every YAML file edited.

## The red-to-green ledger

The mod gives Claude the ledger through a tool of its own, registered with `$.tool.register`. The engine's types (Claude Code 2.1.312, read October 30, 2026) say:
- the model "calls it as `mcp__<plugin>__<name>`", hence `mcp__xcrew__ledger`, which the hook answering it matches by that literal;
- of `isDeferred`: "Left out, the engine's rule places it: behind ToolSearch, as it places an MCP server's tool." The mod leaves it out, so the tool costs a session nothing until Claude searches for it.

A ledger is kept per branch, in `$.store`, under the project's real root and the branch `git symbolic-ref` names. With HEAD detached it is kept under the commit, which a later checkout of a branch never meets again: no attempt is made to carry it over.

A run turns a red green when it ran the test without failing it:
- It must cover the scope where the test fails now: the same tool, scheme and selection, or that tool and scheme's whole suite.
- It must have run every test its scope names. A run with `-skip-testing:` hasn't. Nor has an Xcode MCP test run other than its run of all tests: those tools take their selection in arguments the scope doesn't read, so two `RunSomeTests` runs of different tests would share a scope.
- A failing run counts as well, for the reds it ran that aren't among its failures, as long as it got as far as running tests.

A run whose report the CLI couldn't read is left out, since its outcome would be a guess. Writes happen after the run's result goes back to Claude, one after another, and reading the ledger waits for them.

## What a generator writes

An edit to a file a generator writes is lost on its next generate, so the mod asks the person before one runs. Read October 30, 2026:
- **Tuist** (*Synthesized files*): it will "synthesize the content of those files and write them into the `Derived` directory". That directory is "relative to the directory containing the project that defines them", and the docs say to "add the `Derived` directory to the `.gitignore` file of your project". Tuist also writes the `.xcodeproj` and `.xcworkspace`.
- **XcodeGen** (*ProjectSpec*): "Plists are created on disk on every generation of the project", at a target's `info` or `entitlements` path. The `.xcodeproj` is named by the spec's `name`.

What sits beside a bundle or a `Derived` folder decides whose it is, so each app in a repository is guarded and a dependency's checked-in project isn't:
- An XcodeGen spec writes only the `.xcodeproj` its `name` names, so a workspace CocoaPods wrote beside it isn't XcodeGen's.
- A Tuist manifest, by detection's rule (its ProjectDescription import below the root), writes the project, the workspace and `Derived`.

A Write that creates a file is matched through its nearest existing folder, since `/var` is `/private/var` on disk.

XcodeGen's `info` and `entitlements` paths aren't counted yet, because reading them needs the spec's target keys. The mod's first look matches bundle names as the CLI does, case and all. It reads the whole path, so a project checked out below a folder named `Derived` asks the CLI on every edit, which answers no.

`$.ui.ask`, per the engine's types (Claude Code 2.1.312), "Rejects when dismissed, and in a `-p` run (no one to ask)". Either way the mod refuses the call with the reason, as it did before it asked. The types name no error that tells a dismissal from a failure to show the dialog, so any rejection refuses. A typed answer refuses too, carrying the person's words, rather than the mod reading their intent.

## Toolchains

On October 29, 2026, Swift 6.4.2 (Xcode 27.2 beta 3) on a contributor's Mac accepted a task-group closure that captured a local `Mutex`. CI's Swift job, on the newest Xcode of the `macos-26` runner, rejected it as a `sending` closure that risks a data race. The two compilers don't agree on every concurrency check, so a change that builds locally can still fail CI, and CI's answer is the one that counts. The `macos-26` runner image (version 20261013.0424.1) carries Xcode 26.0.1 to 26.6, and Apple's [Xcode system requirements](https://developer.apple.com/xcode/system-requirements/) put Swift 6.2 in Xcode 26.0 and 26.0.1, 6.2.1 to 6.2.3 in 26.1 to 26.3, and 6.3 in 26.4.1 to 26.6. So CI's newest toolchain was Swift 6.3, older than the contributor's 6.4.2. Each Swift job now prints its toolchain, and a floor job builds and tests on the oldest Xcode whose Swift is the version `Package.swift`'s `swift-tools-version` names.

The first run builds the CLI. The shim used to say "about 10 s" with no measurement behind it. Two cold first builds, `bin/xcrew --version` with an empty Xcrew cache, both on October 29, 2026, under Swift 6.4.2 (Xcode 27.2 beta 3): a fresh Mac took 15.4 s wall clock (`swift build` reported 11.5 s); a contributor's M1 Max (macOS 27.0.1, APFS, Swift's own caches warm) took 13.5 to 14.4 s over three runs (12.0 to 12.4 s). The shim states a range both support, and the README repeats it.

## Tried and rejected

| Option | Why not |
| --- | --- |
| MobileBuildMCP's `incrementalBuildsEnabled` | Slower than plain rebuilds in testing, downloads and runs `xcodemake`, and writes a large `Makefile` into the project root |
| Building through the Xcode MCP by default | Shares and fights Xcode's DerivedData, and follows the person's active scheme |
| Python for Xcrew's logic | Apple's Python is 3.9 and contributors to an iOS tool write Swift; a cached Swift binary also starts faster (about 0.02 s against 0.05 s) |
| Swift scripts | Compiled on every run, about 0.65 s per call, too slow for hooks |
| A shell installer as a third install path | The plugin already installs without mcs, and a third path would drift |
| Counting modules for the build gauge | Nearly every module has a task early in a build, and none says when it's done; see *Build and test progress* |
| Adding expected failures to MobileBuildMCP's counts | The counts are MobileBuildMCP's own, and a result that disagrees with the server's log and summary is harder to trust than one beside a note. Claude gets the true total from Xcrew's note either way |
| `swift-subprocess` | A package dependency means a network fetch on every user's first build |
| Routing build and test tools from their descriptions (`tool.describe`) | Read on October 29, 2026: "Only tool names and server instructions load at session start" ([MCP](https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search)), and the mod API's `tool.describe` fires "at the moment the engine first renders the tool's schema for the model", which for a deferred MCP tool is when ToolSearch loads it. Claude picks the server from names before any description arrives, so a routing line there comes after the choice and can't replace the session briefing |
| Loading MobileBuildMCP's tools up front (`alwaysLoad`) | Claude Code allows it: "set `alwaysLoad` to `true` in that server's configuration … The `alwaysLoad` field is available on all server types" ([MCP](https://code.claude.com/docs/en/mcp)). But MobileBuildMCP 2.7.1's `tools/list` came to 52 tools and 314,229 characters (about 78,000 tokens), mostly input schemas, and "startup [would] wait for the server's tools, capped at the standard 5-second connect timeout". A ToolSearch round trip costs far less. Per-tool `anthropic/alwaysLoad` in a tool's `_meta` is the right granularity, and it's open to whoever owns the server. |
