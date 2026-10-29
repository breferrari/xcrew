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
- **`IDEAllowUnauthenticatedAgents`** lets any unsigned process drive Xcode's tools; leave it off.

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

## How Foundation sees a project's folders

Where Apple's docs are silent, the project search rests on these probes, taken on October 29, 2026 on macOS 27.0.1 with APFS, case-insensitive. Each is pinned by a test in `Tests/XcrewCoreTests/ProjectTests.swift`, so a platform change shows up red.

| Question | Docs | What came back |
| --- | --- | --- |
| Does listing a folder by URL follow a symlink to it? | `contentsOfDirectory(at:…)`: "does not traverse symbolic links" | It throws for a URL that is a symlink to a folder; `contentsOfDirectory(atPath:)` follows it. The search starts from the resolved root |
| Does `resolvingSymlinksInPath()` resolve the `/System/Volumes/Data` firmlink and letter case? | Silent beyond symlinks | Yes: a symlink to the home folder, `/System/Volumes/Data/Users/x` and `/USERS/X` all became `/Users/x`. `canonicalPathKey` alone leaves a final symlink unresolved |
| Is the volume case-insensitive? | `volumeSupportsCaseSensitiveNamesKey` | `false` here. Manifest names match without regard to case only where the volume says so |
| What is standard input: a file, a pipe or a device? | Silent | `FileManager.attributesOfItem(atPath: "/dev/fd/0")` reports `NSFileTypeRegular` for a file, `NSFileTypeUnknown` for a pipe and `NSFileTypeCharacterSpecial` for `/dev/null`; `/dev/stdin` itself reads as a symbolic link. A file is read to its end at once, since waiting on it for more input never ends |
| Which folders are packages? | `isPackageKey`: a package by its extension or by its own flag | True for `.xcodeproj`, `.xcworkspace`, `.app`, `.bundle`, `.playground`, `.xcdatamodeld`; false for `.xcassets`, `.framework`, `.xcframework`, `.lproj`, `.docc`, `.xctestplan` and dotted folders such as `MyApp.iOS`. The search skips a package or an `.xc…` folder, and enters the rest |

## How the plugin directory reads a plugin

From the directory's validation of `main` at two commits on October 29, 2026, beyond what its checklist states. Each is pinned by a test in `Tests/ManifestTests`.

| Observation | What changed |
| --- | --- |
| It resolves a name in the hooks module without regard to scope: a top-level helper that takes `$`, named like a variable inside a hook, reads as `$` passed to that hook's own binding. Claude Code's local `claude plugin validate` reads the same file correctly | The helper and the hook's variable have different names, and a test fails when a helper that takes `$` shares its name with another binding |
| It reads an MCP server's command only when it's a file of the plugin with plain arguments: `xcrun` with `mcpbridge`, and `/bin/sh -c`, were each held as a command it couldn't read | Both local servers start from scripts in `libexec/` |
| It holds a bundled image the README shows with an HTML `<img>` tag; its checklist asks for Markdown's image syntax | The README's images are Markdown, and a test fails on an `<img>` tag |
| Its listing preview shows the README away from the repository: an image at a relative `assets/` path appeared as its alt text | The README's images are absolute `raw.githubusercontent.com` URLs to this repository's `assets/`, and a test fails on any other image source |
| Without `documentationUrl`, the listing took the README's first link, Sosumi's site, as the plugin's documentation | `plugin.json` sets `documentationUrl` and `supportUrl`, and a test fails on a field the manifest reference doesn't document |

## Toolchains

On October 29, 2026, Swift 6.4.2 (Xcode 27.2 beta 3) on a contributor's Mac accepted a task-group closure that captured a local `Mutex`. CI's Swift job, on the newest Xcode of the `macos-26` runner, rejected it as a `sending` closure that risks a data race. The two compilers don't agree on every concurrency check, so a change that builds locally can still fail CI, and CI's answer is the one that counts. The `macos-26` runner image (version 20261013.0424.1) carries Xcode 26.0.1 to 26.6, and Apple's [Xcode system requirements](https://developer.apple.com/xcode/system-requirements/) put Swift 6.2 in Xcode 26.0 and 26.0.1, 6.2.1 to 6.2.3 in 26.1 to 26.3, and 6.3 in 26.4.1 to 26.6. So CI's newest toolchain was Swift 6.3, older than the contributor's 6.4.2. Each Swift job now prints its toolchain, and a floor job builds and tests on the oldest Xcode whose Swift is the version `Package.swift`'s `swift-tools-version` names.

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
