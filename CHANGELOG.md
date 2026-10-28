# Changelog

## Unreleased

- A run far slower than usual says so: `(2× its usual 1:50)` once there are five earlier runs, at 1.5× the average or more.
- After a macro-plugin repair, the toast names the projects that will keep killing plugins until Tuist 4.203 or later regenerates them.
- `/xcrew doctor`, `/xcrew repair` and `/xcrew history`, answered by the mod without a turn for Claude.
- In a generated project, `XcodeWrite`'s description says it's refused there, so Claude reaches for Write first.
- The mod type-checks under `strict` (`scripts/typecheck.sh`), on any machine's set of MCP servers.

## 0.1.0 — 2026-10-28

- Plugin with MobileBuildMCP, the Xcode MCP and Sosumi; a session briefing with the routing rules.
- Mod: macro-plugin repair with retry, build and test timing, the `XcodeWrite` guard.
- Swift CLI: `setup`, `doctor`, `repair-macros`, `xcode-skills`, and the hook entry points.
- mcs techpack installing the plugin, MobileBuildMCP and the per-project setup.
- Runs show in colour on a line above the prompt, live and then with their outcome for a few minutes; the plain status line stays as the fallback where that line can't draw.
- The status line names the scheme and simulator a build or test run uses.
- A build or test run of a minute or more also sends its result as a notification.
- The build and test toast says what failed: the first compile error with its file and line, or how many tests failed and the first one. Failed Xcode MCP builds and test runs now count as failures; the server reports them as normal results.
- The doctor names projects still generated with Tuist's pre-4.203 in-place macro copy phase, and the repair message gives that cause and its fix.
- The macro-plugin repair hook runs only when a build fails with the plugin-kill message, and the doctor skips projects with no macro plugins.
- The `XcodeWrite` guard applies only to generated projects; `xcode-skills` keeps a project's own skills of the same name unless `--force`; setup keeps a managed config that was edited by hand; the README installs per project.
- Macro-plugin repair also covers the indexer's build and Swift packages opened directly, and labels the indexer's copies.
- Setup keeps `.mobilebuildmcp/` out of git; the doctor warns when the config points at a workspace that moved; `xcrew --version`; the CLI cache keeps only the current build.
