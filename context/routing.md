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
- **Before a pull request, to see which changed lines ran:** run the tests through `test_sim` with `"-enableCodeCoverage", "YES"` in `extraArgs`. xcrew then says which of the lines the branch changed that run ran, and which it didn't. Leave it off the edit-and-test loop: it slows the run.
- **DerivedData:** never delete it unless the person asks. If errors persist after `clean`, report what you saw instead.
- **`xcodebuild` and `simctl` through Bash:** only for the project's build scripts, archiving or exporting, and simulator push, URLs, privacy grants, adding photos or videos, creating or shutting one down. All other simulator work goes through MobileBuildMCP, including `erase_sims`, `set_sim_location` and `set_sim_appearance`.
- **Something not working** ("not approved", "produced malformed response", a missing tool, LLDB refusing `expr`): load the `xcrew:reference` skill, and run `xcrew doctor`.
