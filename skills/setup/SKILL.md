---
name: setup
description: Set up xcrew for this iOS project — write MobileBuildMCP's config with the right workspace, schemes and simulators, then check the Mac. Use when the person runs /xcrew:setup, when a session starts with "no .mobilebuildmcp/config.yaml", or when they ask to change which scheme or simulator Claude builds and tests with.
---

# Set up xcrew in this project

1. Run `xcrew doctor` and keep its output for step 5.
2. Find the choices, without asking for what you can look up:
   - **Container:** the `.xcworkspace` (else `.xcodeproj`) nearest the project root, at the root or a folder or two below it; `xcrew setup` picks the same one when you leave out `--container`. In a generated project with none yet, ask the person to generate it first.
   - **Schemes:** MobileBuildMCP's `list_schemes` on that container. Pick the app scheme and, if there is one, the UI-test scheme.
   - **Bundle ID:** `get_app_bundle_id`, or the app target's `PRODUCT_BUNDLE_IDENTIFIER` from `show_build_settings`.
   - **Simulators:** leave them out unless the person names one: setup picks the newest plain iPhone installed.
3. Show the person the choices in one short list and ask them to confirm or change any.
4. Run `xcrew setup --container <name> [--app-scheme <scheme>] [--bundle-id <id>] [--ui-scheme <scheme>] [--test-simulator <name>] [--app-simulator <name>]`. When it reports a config xcrew didn't write, ask before re-running with `--force` (it keeps a backup).
5. Report, from step 1's doctor output and a fresh `xcrew doctor`, each line that isn't `ok` with the command it names. Two need the person once per Mac: `sudo xcrun mcp-server enable`, and approving Claude Code in Xcode's dialog (call `XcodeOpenWorkspace` on the container to raise it).
6. Tell them to restart Claude Code so MobileBuildMCP reads the new config.

Done when `xcrew setup` reported "wrote" and every doctor line is `ok` or explained to the person.
