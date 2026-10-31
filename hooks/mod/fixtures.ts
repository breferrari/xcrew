/**
 * Real results from MobileBuildMCP 2.7.1 and the Xcode MCP (Xcode 27.1), captured against a sample
 * Swift package, with machine paths and identifiers replaced. `isError` is whether the server
 * reported the call as a tool error: the Xcode MCP reports failed builds and failed tests as
 * normal results, and MobileBuildMCP switches from JSON to text when a call fails.
 */
export type Captured = { isError: boolean; text: string }

export const xcodeBuildPassed: Captured = {
  isError: false,
  text: '{"buildResult":"The project built successfully.","elapsedTime":3.857,"errors":[],"fullLogPath":"/var/folders/xx/T/ActionArtifacts/default/BuildProject/BuildProject-Log.txt"}',
}

/** `session_show_defaults` (and `session_set_defaults`, which answers the same shape). */
export const mobileSessionDefaults: Captured = {
  isError: false,
  text: '{"schema":"mobilebuildmcp.output.session-defaults","schemaVersion":"2","didError":false,"error":null,"data":{"currentProfile":"probe","profiles":{"(default)":{"projectPath":null,"workspacePath":null,"scheme":null,"configuration":null,"simulatorName":null,"simulatorId":null,"simulatorPlatform":null,"deviceId":null,"useLatestOS":null,"arch":null,"suppressWarnings":null,"derivedDataPath":null,"preferXcodebuild":null,"platform":null,"bundleId":null,"env":null,"extraArgs":null},"probe":{"projectPath":null,"workspacePath":"/Users/dev/MacroProbe/.swiftpm/xcode/package.xcworkspace","scheme":"MacroProbe-Package","configuration":null,"simulatorName":"iPhone 16","simulatorId":"00000000-0000-0000-0000-000000000000","simulatorPlatform":"iOS Simulator","deviceId":null,"useLatestOS":null,"arch":null,"suppressWarnings":null,"derivedDataPath":null,"preferXcodebuild":null,"platform":null,"bundleId":null,"env":null,"extraArgs":null},"unit":{"projectPath":null,"workspacePath":"/Users/dev/MacroProbe/.swiftpm/xcode/package.xcworkspace","scheme":null,"configuration":null,"simulatorName":"iPhone 12","simulatorId":"00000000-0000-0000-0000-000000000001","simulatorPlatform":"iOS Simulator","deviceId":null,"useLatestOS":null,"arch":null,"suppressWarnings":null,"derivedDataPath":null,"preferXcodebuild":null,"platform":null,"bundleId":null,"env":null,"extraArgs":null}},"operation":{"type":"show"}}}',
}

/** `session_use_defaults_profile`: names the profiles only. */
export const mobileProfileSwitched: Captured = {
  isError: false,
  text: '{"schema":"mobilebuildmcp.output.session-profile","schemaVersion":"2","didError":false,"error":null,"data":{"previousProfile":"probe","currentProfile":"unit"}}',
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
