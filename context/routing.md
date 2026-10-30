## Xcode tooling (xcrew)

Three MCP servers serve this project; their tool names carry the server's (`…xcode__…`, `…MobileBuildMCP__…`, `…sosumi__…`). Pick by job:

| Job | Use |
| --- | --- |
| Build, test (`-only-testing:` through `extraArgs`), coverage, simulators, tapping through the app, LLDB | MobileBuildMCP. Switch setups with `session_use_defaults_profile`, among the profiles named below |
| Compile errors for one file, SwiftUI previews, running a snippet in a module, Organizer crash logs, a physical device | Xcode MCP |
| Apple documentation, with each API's minimum OS version | Sosumi; Xcode's `DocumentationSearch` only offline |
| Creating and editing files | Claude's own Write and Edit. In a Tuist or XcodeGen project, `XcodeWrite` re-saves the generated project file, and the person is asked first; in a classic project, use it when a new file must join a target |
| Project, target, entitlement or build-setting changes | Neither server: edit the project's source of truth (Tuist or XcodeGen manifests, or the project in Xcode) |

- **Compile errors:** trust the Xcode MCP's `XcodeRefreshCodeIssuesInFile`. In a project without a `Package.swift` (a plain Xcode, Tuist or XcodeGen project), Claude Code's SourceKit `No such module` errors are false: it checks each file alone against the macOS SDK.
- **After changing a SwiftUI view** with a `#Preview`, render it with `RenderPreview` in light and dark at a large Dynamic Type size.
- **Before running the whole test suite:** ask the `affected` tool (search for it) which test targets the branch's changes can break, and run those with `-only-testing:`. Its selection covers the targets that own or depend on the changed files, as the project declares them, nothing more. When it says to run the whole suite, run the whole suite.
- **A test fails and the failure doesn't point at your change:** run that test alone through `test_sim` with `extraArgs: ["-only-testing:<Target/Suite/test>", "-test-iterations", "5", "-test-repetition-relaunch-enabled", "YES"]`. xcrew reads each run and says whether it's flaky (failed some runs) or a real failure (failed every run). Fix a real failure. A flaky test stays red until a repeated run passes it every time.
- **A failed test lists `image:` lines** (a snapshot's reference, failing render and difference, or a UI test's screenshots): Read them before changing the code or the reference. Re-record a reference only when the person agrees the new render is right.
- **A UI test fails:** ask the `look` tool (search for it) before changing the test's queries or the view, or rerunning the suite. It gives the steps before the failure, a PNG of the screen at it and, when a query failed, the elements on screen, for each configuration and device it failed on. Read the screen.
- **When writing a pull request's body:** the `evidence` tool (search for it) gives a `## Evidence` block of this branch's recorded test results. Offer it to the person, and add it only if they want it, as it is. Images it lists after the block are attached only if the person agrees; their paths never go in the pull request.
- **Before a pull request, to see which changed lines ran:** run the tests through `test_sim` with `"-enableCodeCoverage", "YES"` in `extraArgs`. xcrew then says which of the lines the branch changed that run ran, and which it didn't. Leave it off the edit-and-test loop: it slows the run.
- **DerivedData:** never delete it unless the person asks. If errors persist after `clean`, report what you saw instead.
- **`xcodebuild` and `simctl` through Bash:** only for the project's build scripts, archiving or exporting, and simulator push, URLs, privacy grants, adding photos or videos, creating or shutting one down. All other simulator work goes through MobileBuildMCP, including `erase_sims`, `set_sim_location`, `set_sim_appearance` and `sim_statusbar`.
- **Something not working** ("not approved", "produced malformed response", a missing tool, LLDB refusing `expr`): load the `xcrew:reference` skill, and run `xcrew doctor`.
