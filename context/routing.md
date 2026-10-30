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
- **SwiftUI previews:** `RenderPreview` renders a view's `#Preview` in any appearance and Dynamic Type size.
- **Affected tests:** the `affected` tool (search for it) names the test targets the branch's changes can break, with the `-only-testing:` arguments that run them. Its selection covers the targets that own or depend on the changed files, as the project declares them, nothing more; when it can't narrow the run, it says to run the whole suite, and why.
- **Flaky or real:** a test run alone and repeated through `test_sim`, with `extraArgs: ["-only-testing:<Target/Suite/test>", "-test-iterations", "5", "-test-repetition-relaunch-enabled", "YES"]`, comes back with xcrew's verdict: flaky (failed some runs) or a real failure (failed every run).
- **A failed test's `image:` lines** show its snapshot's reference, failing render and difference, or a UI test's screenshots. Re-record a reference only when the person agrees the new render is right.
- **A failed UI test:** the `look` tool (search for it) gives the steps leading to the failure, a PNG of the screen at it and, when a query failed, the elements on screen, for each configuration and device it failed on.
- **When writing a pull request's body:** the `evidence` tool (search for it) gives a `## Evidence` block of this branch's recorded test results. Offer it to the person, and add it only if they want it, as it is. Images it lists below the block are attached only if the person agrees; their paths never go in the pull request.
- **Changed-line coverage:** with `"-enableCodeCoverage", "YES"` in `test_sim`'s `extraArgs`, or a scheme or test plan that gathers coverage, xcrew says which of the lines the branch changed the run ran, and which it didn't. Coverage slows a run.
- **DerivedData:** never delete it unless the person asks. If errors persist after `clean`, report what you saw instead.
- **`xcodebuild` and `simctl` through Bash:** only for the project's build scripts, archiving or exporting, and simulator push, URLs, privacy grants, adding photos or videos, creating or shutting one down. All other simulator work goes through MobileBuildMCP, including `erase_sims`, `set_sim_location`, `set_sim_appearance` and `sim_statusbar`.
- **Something not working** ("not approved", "produced malformed response", a missing tool, LLDB refusing `expr`): load the `xcrew:reference` skill, and run `xcrew doctor`.
