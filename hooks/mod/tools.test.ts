import { expect, test } from 'claude-code/testing'
import { kindOf, parseTool, runsSetup } from './tools'

const kind = (name: string) => {
  const tool = parseTool(name)
  return tool ? kindOf(tool) : 'not an Xcode tool'
}

test('build, test and run tools are classified under either registration', () => {
  const cases: [string, string | undefined][] = [
    ['mcp__xcode__BuildProject', 'build'],
    ['mcp__plugin_xcrew_MobileBuildMCP__build_sim', 'build'],
    ['mcp__MobileBuildMCP__build_run_sim', 'build'],
    ['mcp__MobileBuildMCP__build_device', 'build'],
    ['mcp__MobileBuildMCP__clean', 'build'],
    ['mcp__xcode__RunAllTests', 'test'],
    ['mcp__xcode__RunSomeTests', 'test'],
    ['mcp__MobileBuildMCP__test_sim', 'test'],
    // Whole words: "target" holds "get", which marks a tool that only reads.
    ['mcp__xcode__RunTargetTests', 'test'],
    ['mcp__xcode__RunUITests', 'test'],
    ['mcp__xcode__BuildForTesting', 'test'],
    ['mcp__MobileBuildMCP__swift_package_build', 'build'],
    ['mcp__MobileBuildMCP__launch_mac_app', 'run'],
    ['mcp__xcode__RunProject', 'run'],
    ['mcp__MobileBuildMCP__launch_app_sim', 'run'],
    ['mcp__xcode__DeviceInteractionInstallAndRun', 'run'],
  ]
  for (const [name, expected] of cases) expect([name, kind(name)]).toEqual([name, expected])
})

test('tools that only read or inspect are not timed', () => {
  for (const name of [
    'mcp__xcode__GetTestList',
    'mcp__xcode__GetBuildLog',
    'mcp__xcode__XcodeRead',
    'mcp__xcode__RenderPreview',
    'mcp__MobileBuildMCP__list_schemes',
    'mcp__MobileBuildMCP__show_build_settings',
    'mcp__MobileBuildMCP__screenshot',
    // Whole words: "latest" holds "test".
    'mcp__MobileBuildMCP__show_latest_log',
    // A build word doesn't make a reader a build.
    'mcp__MobileBuildMCP__build_settings',
    // Switching what the next run uses isn't a run.
    'mcp__xcode__XcodeSwitchTestPlan',
  ]) {
    expect([name, kind(name)]).toEqual([name, undefined])
  }
})

test('other servers are not Xcode tools', () => {
  expect(kind('mcp__plugin_other_xcode__BuildProject')).toBe('not an Xcode tool')
  expect(kind('Bash')).toBe('not an Xcode tool')
})

test('a shell command that runs xcrew setup is recognised, by any path, quoted or not', () => {
  for (const command of ['xcrew setup', '"/plugins/xcrew/bin/xcrew" setup --app-scheme App', 'cd ios && ~/xcrew/bin/xcrew setup', "'/a b/bin/xcrew' setup", '(xcrew setup)', 'xcrew setup;echo done']) expect(runsSetup(command)).toBe(true)
  for (const command of ['xcrew doctor', 'xcrewsetup', 'echo xcrew setups', 'myxcrew setup']) expect(runsSetup(command)).toBe(false)
})
