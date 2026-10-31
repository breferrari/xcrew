/**
 * Results from MobileBuildMCP 2.7.1 and the Xcode MCP, in shapes captured against a sample Swift
 * package, with machine paths and identifiers replaced. They're hand-kept: nothing regenerates them,
 * and each stays until a test bed capture replaces it (docs/findings.md, *Hand-kept fixtures*,
 * names which). Real MobileBuildMCP test runs are in `replays.ts`. `isError` is whether the server reported the call as a tool
 * error: the Xcode MCP reports failed builds and failed tests as normal results.
 */
export type Captured = { isError: boolean; text: string }

export const xcodeBuildPassed: Captured = {
  isError: false,
  text: '{"buildResult":"The project built successfully.","elapsedTime":3.857,"errors":[],"fullLogPath":"/var/folders/xx/T/ActionArtifacts/default/BuildProject/BuildProject-Log.txt"}',
}

/** `session_show_defaults`, as MobileBuildMCP 2.7.1 answers it: a tree of each profile, with no mark on the one in use. Copied from the test bed's `captures/raw/session-defaults.json`, whose `content` TestbedSessionAnswerTests holds it to. */
export const mobileSessionDefaults: Captured = {
  isError: false,
  text: "\n⚙️ Show Defaults\n\n📁 (default)\n  ├ projectPath: (not set)\n  ├ workspacePath: (not set)\n  ├ scheme: (not set)\n  ├ configuration: (not set)\n  ├ simulatorName: (not set)\n  ├ simulatorId: (not set)\n  ├ simulatorPlatform: (not set)\n  ├ deviceId: (not set)\n  ├ useLatestOS: (not set)\n  ├ arch: (not set)\n  ├ suppressWarnings: (not set)\n  ├ derivedDataPath: (not set)\n  ├ preferXcodebuild: (not set)\n  ├ platform: (not set)\n  ├ bundleId: (not set)\n  ├ env: (not set)\n  └ extraArgs: (not set)\n\n📁 probe\n  ├ projectPath: (not set)\n  ├ workspacePath: /testbed/field/Field.xcworkspace\n  ├ scheme: Feature\n  ├ configuration: (not set)\n  ├ simulatorName: xcrew-testbed\n  ├ simulatorId: (not set)\n  ├ simulatorPlatform: (not set)\n  ├ deviceId: (not set)\n  ├ useLatestOS: (not set)\n  ├ arch: (not set)\n  ├ suppressWarnings: (not set)\n  ├ derivedDataPath: /testbed/DerivedData\n  ├ preferXcodebuild: (not set)\n  ├ platform: (not set)\n  ├ bundleId: (not set)\n  ├ env: (not set)\n  └ extraArgs: (not set)\n\n📁 unit\n  ├ projectPath: (not set)\n  ├ workspacePath: /testbed/field/Field.xcworkspace\n  ├ scheme: Data\n  ├ configuration: (not set)\n  ├ simulatorName: xcrew-testbed\n  ├ simulatorId: (not set)\n  ├ simulatorPlatform: (not set)\n  ├ deviceId: (not set)\n  ├ useLatestOS: (not set)\n  ├ arch: (not set)\n  ├ suppressWarnings: (not set)\n  ├ derivedDataPath: /testbed/DerivedData\n  ├ preferXcodebuild: (not set)\n  ├ platform: (not set)\n  ├ bundleId: (not set)\n  ├ env: (not set)\n  └ extraArgs: (not set)\n",
}

/** The same answer's JSON, in its `structuredContent`, which names the profile in use: what xcrew reads when a result's text is the JSON. */
export const mobileSessionDefaultsJSON: Captured = {
  isError: false,
  text: "{\"schema\":\"mobilebuildmcp.output.session-defaults\",\"schemaVersion\":\"2\",\"didError\":false,\"error\":null,\"data\":{\"currentProfile\":\"probe\",\"profiles\":{\"(default)\":{\"projectPath\":null,\"workspacePath\":null,\"scheme\":null,\"configuration\":null,\"simulatorName\":null,\"simulatorId\":null,\"simulatorPlatform\":null,\"deviceId\":null,\"useLatestOS\":null,\"arch\":null,\"suppressWarnings\":null,\"derivedDataPath\":null,\"preferXcodebuild\":null,\"platform\":null,\"bundleId\":null,\"env\":null,\"extraArgs\":null},\"probe\":{\"projectPath\":null,\"workspacePath\":\"/testbed/field/Field.xcworkspace\",\"scheme\":\"Feature\",\"configuration\":null,\"simulatorName\":\"xcrew-testbed\",\"simulatorId\":null,\"simulatorPlatform\":null,\"deviceId\":null,\"useLatestOS\":null,\"arch\":null,\"suppressWarnings\":null,\"derivedDataPath\":\"/testbed/DerivedData\",\"preferXcodebuild\":null,\"platform\":null,\"bundleId\":null,\"env\":null,\"extraArgs\":null},\"unit\":{\"projectPath\":null,\"workspacePath\":\"/testbed/field/Field.xcworkspace\",\"scheme\":\"Data\",\"configuration\":null,\"simulatorName\":\"xcrew-testbed\",\"simulatorId\":null,\"simulatorPlatform\":null,\"deviceId\":null,\"useLatestOS\":null,\"arch\":null,\"suppressWarnings\":null,\"derivedDataPath\":\"/testbed/DerivedData\",\"preferXcodebuild\":null,\"platform\":null,\"bundleId\":null,\"env\":null,\"extraArgs\":null}},\"operation\":{\"type\":\"show\"}}}",
}

/** `session_use_defaults_profile` to `unit`, as MobileBuildMCP 2.7.1 answers it. Copied from `captures/raw/profile-switched.json`. */
export const mobileProfileSwitched: Captured = {
  isError: false,
  text: "\n⚙️ Use Defaults Profile\n\n✅ Activated profile (unit profile)\n",
}

/** The same answer's JSON, in its `structuredContent`. */
export const mobileProfileSwitchedJSON: Captured = {
  isError: false,
  text: "{\"schema\":\"mobilebuildmcp.output.session-profile\",\"schemaVersion\":\"2\",\"didError\":false,\"error\":null,\"data\":{\"previousProfile\":\"probe\",\"currentProfile\":\"unit\"}}",
}

/** What `xcrew session` answers for `mobileSessionDefaults`, which the mod's tests stub the CLI with; TestbedSessionAnswerTests holds it to the CLI. */
export const mobileSessionDefaultsRead: Captured = {
  isError: false,
  text: "{\"profiles\":{\"(default)\":{},\"probe\":{\"scheme\":\"Feature\",\"simulatorName\":\"xcrew-testbed\"},\"unit\":{\"scheme\":\"Data\",\"simulatorName\":\"xcrew-testbed\"}}}",
}

/** What `xcrew session` answers for `mobileProfileSwitched`. */
export const mobileProfileSwitchedRead: Captured = {
  isError: false,
  text: "{\"currentProfile\":\"unit\"}",
}

/** `XcodeOpenWorkspace`. */
export const xcodeWorkspaceOpened: Captured = {
  isError: false,
  text: '{"activeRunDestination":"My Mac","activeScheme":"MacroProbe-Package","workspaceIdentifier":"workspace-0000000000","workspacePath":"/Users/dev/MacroProbe"}',
}

/** `XcodeSwitchScheme`: names the scheme `activeSchemeName`, where `XcodeOpenWorkspace` says `activeScheme`. */
export const xcodeSchemeSwitched: Captured = {
  isError: false,
  text: '{"activeDestinationDisplayTitle":"iPhone 18 Pro","activeSchemeName":"MacroProbe","message":"Active scheme is now \'MacroProbe\' with run destination \'iPhone 18 Pro\'."}',
}
