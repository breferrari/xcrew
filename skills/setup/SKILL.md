---
name: setup
description: Set up xcrew for this iOS project — write MobileBuildMCP's config with the right workspace, schemes and simulators, then check the Mac. Use when the person runs /xcrew:setup, when a session starts with "no .mobilebuildmcp/config.yaml", or when they ask to change which scheme or simulator Claude builds and tests with.
---

# Set up xcrew in this project

1. Find the choices, without asking for what you can look up:
   - **Container:** run `xcrew project --setup`. Its JSON names the `container` setup will build. When it has a `containerProblem` instead, explain it to the person in your own words and ask: which of the folders it lists to use, or to generate the workspace first, then run `xcrew project --setup` again.
   - **Schemes:** MobileBuildMCP's `list_schemes` on that container. Pick the app scheme and, if there is one, the UI-test scheme. Leave the unit-test scheme to `xcrew setup`.
   - **Bundle ID:** `get_app_bundle_id`, or the app target's `PRODUCT_BUNDLE_IDENTIFIER` from `show_build_settings`.
   - **Simulators:** leave them out unless the person names one: setup picks the newest plain iPhone installed.
2. Show the person the choices in one short list and ask them to confirm or change any.
3. Run `xcrew setup [--container <name>] [--app-scheme <scheme>] [--bundle-id <id>] [--ui-scheme <scheme>] [--test-scheme <scheme>] [--test-simulator <name>] [--app-simulator <name>]` on its own, not chained to another command. Pass `--container` only when the person named or chose one. Tell the person which scheme it chose for unit tests; when it lists several, or couldn't tell, ask which one runs them and re-run with `--test-scheme`. When it reports a config xcrew didn't write, ask before re-running with `--force` (it keeps a backup).
4. Run `xcrew doctor` on its own and report each line that isn't `ok` with the command it names. It exits non-zero when a check failed or warned: that's the doctor's verdict, not a failed setup. Two fixes need the person once per Mac: `sudo xcrun mcp-server enable`, and approving Claude Code in Xcode's dialog (call `XcodeOpenWorkspace` on the container to raise it).
5. Tell them to restart Claude Code so MobileBuildMCP reads the new config.

Done when `xcrew setup` reported "wrote" and every doctor line is `ok` or explained to the person.
