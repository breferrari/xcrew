import { expect, test } from 'claude-code/testing'
import { buildsProject, generatedApps, generatedPart, kindOf, mayBeGenerated, mayBeManifest, parseTool, runsGenerate, runsSetup } from './tools'

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

test('a file a generator may read is recognised by its name, in any case, and other files are not', () => {
  // The names ProjectLayout gives Tuist's markers and manifests and XcodeGen's spec, and Tuist's own folder.
  for (const path of ['/a/Tuist.swift', '/a/Project.swift', '/a/Workspace.swift', '/a/project.yml', '/a/ios/PROJECT.SWIFT', '/a/Tuist/ProjectDescriptionHelpers/Targets.swift', '/a/Tuist/Package.swift', 'Project.swift', '/a/targets/App.yml', '/a/specs/Shared.YAML']) {
    expect([path, mayBeManifest(path)]).toEqual([path, true])
  }
  for (const path of ['/a/ContentView.swift', '/a/MyProject.swift', '/a/project.yml.orig', '/a/Tuistery/Package.swift', '/a/Package.swift']) expect([path, mayBeManifest(path)]).toEqual([path, false])
})

test('a shell command that regenerates the project is recognised, alone or among others', () => {
  // The commands `xcrew project --manifest` names, and the generators' shorter spellings.
  for (const command of ['tuist generate --no-open', 'tuist generate --no-open --path ios', 'xcodegen generate', 'xcodegen generate --spec ios/project.yml', 'cd ios && tuist generate', 'xcodegen', 'xcodegen --spec ios/project.yml', 'mise exec -- tuist generate --no-open']) {
    expect([command, runsGenerate(command)]).toEqual([command, true])
  }
  for (const command of ['tuist install', 'tuist edit', 'xcodegen dump', 'xcodegen version', 'echo generate', 'mytuist generate']) expect([command, runsGenerate(command)]).toEqual([command, false])
})

test('a generate counts only when its exit status is the command\'s, by any path to the generator', () => {
  for (const command of ['tuist install && tuist generate --no-open', 'tuist install --path ios && tuist generate --no-open --path ios', '/opt/homebrew/bin/tuist generate --no-open', './bin/xcodegen generate', 'xcodegen generate 2>&1', 'tuist generate --no-open > generate.log 2>&1', 'tuist generate && echo done']) {
    expect([command, runsGenerate(command)]).toEqual([command, true])
  }
  // A later command's status hides the generate's: a failed generate would read as a success.
  for (const command of ['tuist generate --no-open 2>&1 | tail -5', 'tuist generate; echo done', 'tuist generate || true', 'tuist generate &', 'tuist generate\necho done']) {
    expect([command, runsGenerate(command)]).toEqual([command, false])
  }
})

test('only tools that build the project are held back after a manifest edit', () => {
  const builds = (name: string) => {
    const tool = parseTool(name)
    return tool ? buildsProject(tool) : 'not an Xcode tool'
  }
  // RunProject builds before it launches; a launch alone runs what was built.
  for (const name of ['mcp__MobileBuildMCP__build_sim', 'mcp__MobileBuildMCP__build_run_sim', 'mcp__MobileBuildMCP__test_sim', 'mcp__xcode__BuildProject', 'mcp__xcode__RunAllTests', 'mcp__xcode__RunProject']) expect([name, builds(name)]).toEqual([name, true])
  for (const name of ['mcp__MobileBuildMCP__clean', 'mcp__MobileBuildMCP__launch_app_sim', 'mcp__MobileBuildMCP__launch_mac_app', 'mcp__xcode__GetBuildLog']) expect([name, builds(name)]).toEqual([name, false])
})

test('a shell command that runs xcrew setup is recognised, by any path, quoted or not', () => {
  for (const command of ['xcrew setup', '"/plugins/xcrew/bin/xcrew" setup --app-scheme App', 'cd ios && ~/xcrew/bin/xcrew setup', "'/a b/bin/xcrew' setup", '(xcrew setup)', 'xcrew setup;echo done']) expect(runsSetup(command)).toBe(true)
  for (const command of ['xcrew doctor', 'xcrewsetup', 'echo xcrew setups', 'myxcrew setup']) expect(runsSetup(command)).toBe(false)
})

test('the app each generate names is read from its own option or a cd before it, and none is named without either', () => {
  const cases: [string, (string | undefined)[]][] = [
    ['tuist generate --no-open --path apps/b', ['apps/b']],
    ['tuist generate -p ./apps/b/ --no-open', ['apps/b']],
    ["tuist generate --no-open --path 'my apps/b'", ['my apps/b']],
    ['tuist generate --path=apps/b', ['apps/b']],
    ['tuist generate --no-open --path ios', ['ios']],
    ['tuist install --path ios && tuist generate --no-open --path ios', ['ios']],
    ['tuist install && tuist generate --no-open', [undefined]],
    ['tuist generate --no-open --path /work/Repo/apps/a', ['/work/Repo/apps/a']],
    ['xcodegen generate --spec ios/project.yml', ['ios']],
    ['xcodegen -s ./ios/project.yml', ['ios']],
    // XcodeGen's `-p` is the folder it writes to, not the spec it reads.
    ['xcodegen generate -p build', [undefined]],
    ['cd ios && tuist generate --no-open', ['ios']],
    ['cd apps/a && tuist generate --no-open && cd ../b && tuist generate --no-open', ['apps/a', '../b']],
    ['tuist generate --no-open --path apps/a && tuist generate --no-open --path apps/b', ['apps/a', 'apps/b']],
    ['tuist generate --no-open', [undefined]],
    ['xcodegen generate', [undefined]],
    ['echo nothing', []],
  ]
  for (const [command, apps] of cases) expect([command, generatedApps(command)]).toEqual([command, apps])
})

test('a path inside a bundle or Derived folder may be generated; others are not asked about', () => {
  // The bundles ProjectLayout counts as Xcode containers, and Tuist's Derived folder.
  for (const path of ['/a/App.xcodeproj/project.pbxproj', '/a/App.xcworkspace/contents.xcworkspacedata', '/a/Derived/InfoPlists/App-Info.plist']) {
    expect([path, mayBeGenerated(path)]).toEqual([path, true])
  }
  // The CLI matches bundle extensions as written, so another case isn't asked about.
  for (const path of ['/a/App/ContentView.swift', '/a/Derivedness/x.swift', '/a/App.xcodeproj', '/a/Project.swift', '/a/ios/APP.XCODEPROJ/project.pbxproj']) expect([path, mayBeGenerated(path)]).toEqual([path, false])
})

test('a generated file is shown from its bundle or Derived folder on', () => {
  expect(generatedPart('/work/App/ios/App.xcodeproj/project.pbxproj')).toBe('App.xcodeproj/project.pbxproj')
  expect(generatedPart('/work/App/Derived/InfoPlists/App-Info.plist')).toBe('Derived/InfoPlists/App-Info.plist')
})
