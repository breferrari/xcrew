## Xcode tooling (xcrew)

Three MCP servers serve this project; their tool names carry the server's (`…xcode__…`, `…MobileBuildMCP__…`, `…sosumi__…`). Pick by job:

| Job | Use |
| --- | --- |
| Build, test (`-only-testing:` through `extraArgs`), coverage, simulators, tapping through the app, LLDB | MobileBuildMCP. Switch setups with `session_use_defaults_profile`, among the profiles named below |
| Compile errors for one file, SwiftUI previews, running a snippet in a module, Organizer crash logs, a physical device | Xcode MCP |
| Apple documentation, with each API's minimum OS version | Sosumi; Xcode's `DocumentationSearch` only offline |
| Creating and editing files | Claude's own Write and Edit. In a Tuist or XcodeGen project, `XcodeWrite` re-saves the generated project file and is refused; in a classic project, use it when a new file must join a target |
| Project, target, entitlement or build-setting changes | Neither server: edit the project's source of truth (Tuist or XcodeGen manifests, or the project in Xcode) |

- **Compile errors:** trust the Xcode MCP's `XcodeRefreshCodeIssuesInFile`. In a project without a `Package.swift` (a plain Xcode, Tuist or XcodeGen project), Claude Code's SourceKit `No such module` errors are false: it checks each file alone against the macOS SDK.
- **After changing a SwiftUI view** with a `#Preview`, render it with `RenderPreview` in light and dark at a large Dynamic Type size.
- **Something not working** ("not approved", "produced malformed response", a missing tool, LLDB refusing `expr`): load the `xcrew:reference` skill, and run `xcrew doctor`.
