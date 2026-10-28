/**
 * Real results from MobileBuildMCP 2.7.1 and the Xcode MCP (Xcode 27.1), captured against a sample
 * Swift package, with machine paths and identifiers replaced. `isError` is whether the server
 * reported the call as a tool error: the Xcode MCP reports failed builds and failed tests as
 * normal results, and MobileBuildMCP switches from JSON to text when a call fails.
 */
export type Captured = { isError: boolean; text: string }

export const mobileTestsPassed: Captured = {
  isError: false,
  text: '{"schema":"mobilebuildmcp.output.test-result","schemaVersion":"3","didError":false,"error":null,"data":{"summary":{"status":"SUCCEEDED","durationMs":14544,"counts":{"passed":3,"failed":0,"skipped":0},"target":"simulator"},"artifacts":{"buildLogPath":"~/Library/Developer/MobileBuildMCP/workspaces/sample-0000/logs/test_sim.log","xcresultPath":"~/Library/Developer/MobileBuildMCP/workspaces/sample-0000/result-bundles/test_sim.xcresult","testProductsPath":"~/Library/Developer/MobileBuildMCP/workspaces/sample-0000/test-products/test_sim.xctestproducts"},"diagnostics":{"warnings":[],"errors":[],"testFailures":[]},"testCases":[{"suite":"PlainTests","test":"testAddition","status":"passed","durationMs":1},{"suite":"PlainTests","test":"testComparison","status":"passed","durationMs":0},{"suite":"PlainTests","test":"testConcatenation","status":"passed","durationMs":0}]}}',
}

export const mobileTestsFailed: Captured = {
  isError: true,
  text: `🧪 Test

Test Failures (2):

  ✗ PlainTests / testConcatenation: XCTAssertEqual failed: ("ab") is not equal to ("ba") - strings join left to right
    /Users/dev/MacroProbe/Tests/PlainTests/PlainTests.swift:5

  ✗ PlainTests / testConcatenation(): XCTAssertEqual failed: ("ab") is not equal to ("ba") - strings join left to right

Test Results:
  ✅ PlainTests/testAddition (0.001s)
  ✅ PlainTests/testComparison (0.000s)
  ❌ PlainTests/testConcatenation (0.596s)

❌ 1 test failed, 2 passed, 0 skipped (⏱️ 12.3s)
  └ Files:
     └── ~/Library/Developer/MobileBuildMCP/workspaces/sample-0000/
         ├── logs/test_sim.log — Build Logs
         ├── result-bundles/test_sim.xcresult — Result Bundle
         └── test-products/test_sim.xctestproducts — Test Products`,
}

/** A test run that never reached its tests, because the build of the test target failed. */
export const mobileTestsBuildFailed: Captured = {
  isError: true,
  text: `🧪 Test

Errors (2):

  ✗ LLVM Profile Error: Failed to write file "default.profraw": Operation not permitted

  ✗ Failed to build workspace MacroProbe with scheme MacroProbe-Package.: Cannot test target “MacroProbeTests” on “iPhone 16”: Missing test product at /Users/dev/Library/Developer/MobileBuildMCP/workspaces/sample-0000/test-products/test_sim.xctestproducts/Tests/0/Debug-iphonesimulator/MacroProbeTests.xctest

❌ Test failed. (⏱️ 14.8s)
  └ Files:
     └── ~/Library/Developer/MobileBuildMCP/workspaces/sample-0000/
         ├── logs/test_sim.log — Build Logs
         ├── result-bundles/test_sim.xcresult — Result Bundle
         └── test-products/test_sim.xctestproducts — Test Products`,
}

export const mobileBuildPassed: Captured = {
  isError: false,
  text: '{"schema":"mobilebuildmcp.output.build-result","schemaVersion":"3","didError":false,"error":null,"data":{"summary":{"status":"SUCCEEDED","durationMs":2495,"target":"simulator"},"artifacts":{"buildLogPath":"~/Library/Developer/MobileBuildMCP/workspaces/sample-0000/logs/build_sim.log"},"diagnostics":{"warnings":[],"errors":[]}},"nextSteps":["Get built app path in simulator derived data: get_sim_app_path({ simulatorId: \\"00000000-0000-0000-0000-000000000000\\", scheme: \\"MacroProbe-Package\\", platform: \\"iOS Simulator\\" })"]}',
}

export const mobileBuildFailed: Captured = {
  isError: true,
  text: `🔨 Build

Errors (2):

  ✗ cannot convert value of type 'String' to specified type 'Int'
    /Users/dev/MacroProbe/Sources/MacroProbe/MacroProbe.swift:13

  ✗ |                        \`- error: cannot convert value of type 'String' to specified type 'Int'

❌ Build failed. (⏱️ 3.2s)
  └ Files:
     └── ~/Library/Developer/MobileBuildMCP/workspaces/sample-0000/logs/build_sim.log — Build Logs`,
}

export const xcodeBuildPassed: Captured = {
  isError: false,
  text: '{"buildResult":"The project built successfully.","elapsedTime":3.857,"errors":[],"fullLogPath":"/var/folders/xx/T/ActionArtifacts/default/BuildProject/BuildProject-Log.txt"}',
}

export const xcodeBuildFailed: Captured = {
  isError: false,
  text: '{"buildResult":"The build failed; errors are summarized in the `errors` field of the output.","elapsedTime":0.758,"errors":[{"classification":"error","filePath":"/Users/dev/MacroProbe/Sources/MacroProbe/MacroProbe.swift","lineNumber":13,"message":"Cannot convert value of type \'String\' to specified type \'Int\'"}],"fullLogPath":"/var/folders/xx/T/ActionArtifacts/default/BuildProject/BuildProject-Log.txt"}',
}

export const xcodeTestsPassed: Captured = {
  isError: false,
  text: '{"activeTestPlanName":"MacroProbe-Package","counts":{"expectedFailures":0,"failed":0,"notRun":0,"passed":5,"skipped":0,"total":5},"results":[{"displayName":"testMacro()","errorMessages":[],"identifier":"MacroProbeTests/testMacro()","state":"Passed","targetName":"MacroProbeTests"},{"displayName":"testMacroWithStringLiteral()","errorMessages":[],"identifier":"MacroProbeTests/testMacroWithStringLiteral()","state":"Passed","targetName":"MacroProbeTests"},{"displayName":"testAddition()","errorMessages":[],"identifier":"PlainTests/testAddition()","state":"Passed","targetName":"PlainTests"},{"displayName":"testConcatenation()","errorMessages":[],"identifier":"PlainTests/testConcatenation()","state":"Passed","targetName":"PlainTests"},{"displayName":"testComparison()","errorMessages":[],"identifier":"PlainTests/testComparison()","state":"Passed","targetName":"PlainTests"}],"schemeName":"MacroProbe-Package","summary":"5 tests: 5 passed, 0 failed, 0 skipped, 0 expected failures, 0 not run","totalResults":5,"truncated":false}',
}

export const xcodeTestsFailed: Captured = {
  isError: false,
  text: '{"activeTestPlanName":"MacroProbe-Package","counts":{"expectedFailures":0,"failed":3,"notRun":0,"passed":2,"skipped":0,"total":5},"results":[{"displayName":"testMacro()","errorMessages":["MacroProbe/Tests/MacroProbeTests/MacroProbeTests.swift:19 MacroProbeTests/testMacro(): Issue recorded: Macro expansion did not produce the expected expanded source"],"identifier":"MacroProbeTests/testMacro()","state":"Failed","targetName":"MacroProbeTests"},{"displayName":"testMacroWithStringLiteral()","errorMessages":["MacroProbe/Tests/MacroProbeTests/MacroProbeTests.swift:35 MacroProbeTests/testMacroWithStringLiteral(): Issue recorded: Macro expansion did not produce the expected expanded source"],"identifier":"MacroProbeTests/testMacroWithStringLiteral()","state":"Failed","targetName":"MacroProbeTests"},{"displayName":"testConcatenation()","errorMessages":["MacroProbe/Tests/PlainTests/PlainTests.swift:5 PlainTests/testConcatenation(): XCTAssertEqual failed: (\\"ab\\") is not equal to (\\"ba\\") - strings join left to right"],"identifier":"PlainTests/testConcatenation()","state":"Failed","targetName":"PlainTests"},{"displayName":"testAddition()","errorMessages":[],"identifier":"PlainTests/testAddition()","state":"Passed","targetName":"PlainTests"},{"displayName":"testComparison()","errorMessages":[],"identifier":"PlainTests/testComparison()","state":"Passed","targetName":"PlainTests"}],"schemeName":"MacroProbe-Package","summary":"5 tests: 2 passed, 3 failed, 0 skipped, 0 expected failures, 0 not run","totalResults":5,"truncated":false}',
}

/** The Xcode MCP's answer when the build before a test run fails. */
export const xcodeTestsBuildFailed: Captured = {
  isError: true,
  text: '{"type":"error","data":"Build action failed. Inspect build logs."}',
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
