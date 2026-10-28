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
- **Macro plugins die after an in-place rewrite.** The kernel caches a Mach-O file's code signature and doesn't flush that cache when the file is rewritten in place, so the next launch is killed; Apple's guidance is to replace such a file rather than overwrite it ([Apple Developer Forums](https://developer.apple.com/forums/thread/130313)). **The trigger is the macro copy phase older Tuist versions generate.** Up to Tuist 4.202, for each macro target, Tuist generates a Run Script phase that copies the macOS-built plugin into the products folder of a non-macOS destination (`Debug-iphonesimulator/`) with `cp -f`, which writes into the existing file and keeps its inode. Reproduced directly: with a copy of a plugin running, as the compiler and the indexer keep them, `cp -f`-ing a new build over it makes every later launch of that path exit with SIGKILL, while a copy-and-rename over it runs again. Seen with Tuist 4.202.8. Tuist 4.203.0 removed the phase ([tuist#11825](https://github.com/tuist/tuist/pull/11825): "the macro executable copy build phase has been removed"), so projects generated with 4.203 or later don't have this trigger; upgrading Tuist and regenerating is the real fix, and the repair covers projects still generated with an older one, or any other build step that copies plugins in place. It hits the regular build and the indexer's (`Index.noindex/Build/Products`) alike; a dead indexer copy breaks macro expansion in the editor without any failing build. Xcode's own linking doesn't trigger it: a plain Swift macro package rebuilt three times in Xcode 27.1 got a new inode each time and never died. The build reports "produced malformed response"; the repair is to copy the bytes beside the plugin and rename the copy over it, and probing a plugin means sending the compiler's own capability request. The same message also comes from other causes, such as a toolchain mismatch or stale prebuilt macros, which the repair doesn't address: it finds no dead plugin and changes nothing.
- **SourceKit can't read Xcode projects.** Claude Code's Swift language server reads settings only from a Swift package, a compilation database or a build server. Without a `Package.swift` it checks each file alone against the macOS SDK, so `import UIKit` and every first-party module show as errors. The Xcode MCP's `XcodeRefreshCodeIssuesInFile` uses the real settings.
- **The XcodeBuildMCP → MobileBuildMCP rename (2.7.1) has no fallback.** The binary, the `MOBILEBUILDMCP_*` variables and the config folder (`.mobilebuildmcp/`) all changed; an old `.xcodebuildmcp/config.yaml` is ignored silently, leaving only the simulator tools. An old binary on `PATH`, from Homebrew or npm, can shadow the new one.
- **MobileBuildMCP reads its config from its working directory**, so the plugin starts it in the project root.
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

## Tried and rejected

| Option | Why not |
| --- | --- |
| MobileBuildMCP's `incrementalBuildsEnabled` | Slower than plain rebuilds in testing, downloads and runs `xcodemake`, and writes a large `Makefile` into the project root |
| Building through the Xcode MCP by default | Shares and fights Xcode's DerivedData, and follows the person's active scheme |
| Python for Xcrew's logic | Apple's Python is 3.9 and contributors to an iOS tool write Swift; a cached Swift binary also starts faster (about 0.02 s against 0.05 s) |
| Swift scripts | Compiled on every run, about 0.65 s per call, too slow for hooks |
| A shell installer as a third install path | The plugin already installs without mcs, and a third path would drift |
| Counting modules for the build gauge | Nearly every module has a task early in a build, and none says when it's done; see *Build and test progress* |
| `swift-subprocess` | A package dependency means a network fetch on every user's first build |
