import { expect, mock, test } from 'claude-code/testing'
import type { On, ToolCallResult } from 'claude-code'
import { callTool, stubCli, type CliCall } from './testing'
import { isUndone, marked } from './regenerate'

const GENERATE = 'tuist generate --no-open --path ios'
const MANIFEST = '/work/App/ios/Project.swift'
const DEPENDENCIES = '/work/App/ios/Tuist/Package.swift'

/**
 * A Tuist project whose CLI names `GENERATE` for an edit to `MANIFEST` and nothing for any other file, and gives each
 * file's hash by how far edits have moved it: an edit from `a` to `b` or a Write moves it on, one from `b` to `a` back. Beneath
 * the mod, every tool answers, and a Bash command fails when `failing` holds it.
 */
function tuistProject(on: On, failing: string[] = [], hashes: { hold?: () => Promise<void> } = {}): CliCall[] {
  mock.store(on)
  const versions = new Map<string, number>()
  const hashArgument = (args: readonly string[]) => args[args.indexOf('--hash') + 1] ?? ''
  const calls = stubCli(on, {
    project: async args => {
      if (args.includes('--hash')) await hashes.hold?.()
      return {
        isGenerated: true,
        ...(args.includes('--manifest') && [MANIFEST, DEPENDENCIES].some(file => args.includes(file)) ? { generate: GENERATE, app: 'ios' } : {}),
        ...(args.includes('--hash') ? { hash: `v${versions.get(hashArgument(args)) ?? 0}` } : {}),
      }
    },
  })
  on('tool.call', (_, e) => {
    if (e.tool === 'Bash' && failing.includes(e.command)) return { isError: true, result: 'Exit code 1', text: 'Exit code 1' }
    if (e.tool === 'Edit') versions.set(e.file_path, (versions.get(e.file_path) ?? 0) + (e.new_string === 'a' ? -1 : 1))
    if (e.tool === 'Write') versions.set(e.file_path, (versions.get(e.file_path) ?? 0) + 1)
    return { result: {}, text: 'done' }
  })
  return calls
}

const editManifest = (tool: Parameters<typeof callTool>[0]) => callTool(tool, 'Edit', { file_path: MANIFEST, old_string: 'a', new_string: 'b' })
const undoEdit = (tool: Parameters<typeof callTool>[0]) => callTool(tool, 'Edit', { file_path: MANIFEST, old_string: 'b', new_string: 'a' })
const build = (tool: Parameters<typeof callTool>[0], name = 'mcp__plugin_xcrew_MobileBuildMCP__build_sim') => callTool(tool, name)
const contextOf = (result: ToolCallResult) => (result.context ?? []).join('\n')

test('after a manifest edit the first build is refused with the command that regenerates the project', async ($, on) => {
  tuistProject(on)
  await editManifest($)
  const refused = await build($)
  expect(refused.deny).toContain(`\`${GENERATE}\``)
})

test('a build MobileBuildMCP forwards to the Xcode MCP is refused after a manifest edit too', async ($, on) => {
  tuistProject(on)
  await editManifest($)
  const refused = await callTool($, 'mcp__MobileBuildMCP__xcode_ide_call_tool', { remoteTool: 'BuildProject', arguments: '{}' })
  expect(refused.deny).toContain(`\`${GENERATE}\``)
})

/** An edit undone leaves the manifests as the last generate read them: nothing to generate, so nothing is refused. */
test('a manifest edit undone before the build lets the build run', async ($, on) => {
  tuistProject(on)
  await editManifest($)
  await undoEdit($)
  const built = await build($)
  expect(built.deny).toBeUndefined()
  expect(contextOf(built)).not.toContain(GENERATE)
})

/** Undone, then edited again: the manifests differ from the last generate's once more. */
test('an edit made again after an undo is refused again', async ($, on) => {
  tuistProject(on)
  await editManifest($)
  await undoEdit($)
  await editManifest($)
  expect((await build($)).deny).toContain(GENERATE)
})

/** Refused, the person may have generated from the edit in their own terminal: an undo then leaves that project stale. */
test('an edit undone after its build was refused still holds the build back', async ($, on) => {
  tuistProject(on)
  await editManifest($)
  await build($)
  await undoEdit($)
  expect((await build($)).deny).toContain(GENERATE)
})

/** Of two edited files, one undone leaves the other's edit standing. */
test('an app with one of two edits undone is still refused', async ($, on) => {
  tuistProject(on)
  await editManifest($)
  await callTool($, 'Edit', { file_path: DEPENDENCIES, old_string: 'a', new_string: 'b' })
  await undoEdit($)
  expect((await build($)).deny).toContain(GENERATE)
})

/** An edit made while a build reads the hashes is kept: what was undone goes, not what the build read before. */
test('an edit made while a build reads the hashes keeps its mark', async ($, on) => {
  let release = () => {}
  let reached = () => {}
  let holding = false
  const held = new Promise<void>(resolve => (release = resolve))
  const reading = new Promise<void>(resolve => (reached = resolve))
  tuistProject(on, [], { hold: () => (holding ? (reached(), held) : Promise.resolve()) })
  await editManifest($)
  await undoEdit($)
  holding = true
  const building = build($)
  await reading
  holding = false
  await callTool($, 'Edit', { file_path: DEPENDENCIES, old_string: 'a', new_string: 'b' })
  release()
  expect((await building).deny).toContain(GENERATE)
})

/** A mark an older mod saved names no file: its edit can't be told undone, and a later file's hash doesn't change that. */
test('a mark without files keeps its edit standing when a file is added to it', () => {
  const stale = marked({ marks: [{ app: 'ios', generate: GENERATE }], refused: false }, { app: 'ios', generate: GENERATE }, { path: DEPENDENCIES, before: 'v0' })
  const mark = stale.marks[0]
  expect(mark && isUndone(mark, { [DEPENDENCIES]: 'v0' })).toBe(false)
})

test('a second build without a generate goes through, says why, and the next one runs plainly', async ($, on) => {
  tuistProject(on)
  await editManifest($)
  await build($)
  const second = await build($)
  expect(second.deny).toBeUndefined()
  expect(contextOf(second)).toContain(GENERATE)
  // The mark is gone: the person may have generated in their own terminal, which the mod can't see.
  const third = await build($)
  expect(third.deny).toBeUndefined()
  expect(contextOf(third)).not.toContain(GENERATE)
})

test('the edit itself says the generated project changes only after the command', async ($, on) => {
  tuistProject(on)
  const edited = await editManifest($)
  expect(contextOf(edited)).toContain(`\`${GENERATE}\``)
})

test('a generate that succeeds clears the mark, so the build runs', async ($, on) => {
  tuistProject(on)
  await editManifest($)
  await callTool($, 'Bash', { command: `cd /work/App && ${GENERATE}` })
  expect((await build($)).deny).toBeUndefined()
})

test('a generate that fails leaves the mark, so the build is still refused', async ($, on) => {
  tuistProject(on, [GENERATE])
  await editManifest($)
  await callTool($, 'Bash', { command: GENERATE })
  expect((await build($)).deny).toContain(GENERATE)
})

test('a generate sent to the background clears nothing: it has not finished when the call returns', async ($, on) => {
  tuistProject(on)
  await editManifest($)
  await callTool($, 'Bash', { command: GENERATE, run_in_background: true })
  expect((await build($)).deny).toContain(GENERATE)
})

test('Write marks the project as Edit does, and test runs are refused under either registration', async ($, on) => {
  tuistProject(on)
  await callTool($, 'Write', { file_path: MANIFEST, content: 'import ProjectDescription' })
  expect((await build($, 'mcp__xcode__RunAllTests')).deny).toContain(GENERATE)
  await callTool($, 'Write', { file_path: MANIFEST, content: 'import ProjectDescription' })
  expect((await build($, 'mcp__plugin_xcrew_xcode__BuildProject')).deny).toContain(GENERATE)
})

test('an edit to a file no generator reads marks nothing, and only names a manifest might have are asked about', async ($, on) => {
  const calls = tuistProject(on)
  await callTool($, 'Edit', { file_path: '/work/App/ios/App/ContentView.swift', old_string: 'a', new_string: 'b' })
  // A source file named like a manifest is asked about, and the CLI says it isn't one.
  await callTool($, 'Edit', { file_path: '/work/App/ios/App/Models/Project.swift', old_string: 'a', new_string: 'b' })
  expect((await build($)).deny).toBeUndefined()
  expect(calls.filter(call => call.args.includes('--manifest')).map(call => call.args.at(-1))).toEqual(['/work/App/ios/App/Models/Project.swift'])
})

test('an edit that failed marks nothing', async ($, on) => {
  mock.store(on)
  stubCli(on, { project: () => ({ isGenerated: true, generate: GENERATE, app: 'ios' }) })
  on('tool.call', (_, e) => (e.tool === 'Edit' ? { isError: true, result: 'String not found', text: 'String not found' } : { result: {} }))
  await editManifest($)
  expect((await build($)).deny).toBeUndefined()
})

test('when the CLI can\'t answer, an edit marks nothing and builds run', async ($, on) => {
  mock.store(on)
  on('process.run', () => {
    throw new Error('xcrew not built')
  })
  on('tool.call', () => ({ result: {} }))
  const edited = await editManifest($)
  expect(edited.isError).toBeUndefined()
  expect((await build($)).deny).toBeUndefined()
})

test('a clean or a launch after a manifest edit runs, and leaves the refusal for the build', async ($, on) => {
  tuistProject(on)
  await editManifest($)
  expect((await callTool($, 'mcp__MobileBuildMCP__clean')).deny).toBeUndefined()
  expect((await callTool($, 'mcp__MobileBuildMCP__launch_app_sim')).deny).toBeUndefined()
  expect((await build($)).deny).toContain(GENERATE)
})

test('a generate piped into another command clears nothing: the pipe\'s status is the last command\'s', async ($, on) => {
  tuistProject(on)
  await editManifest($)
  await callTool($, 'Bash', { command: `${GENERATE} 2>&1 | tail -5` })
  expect((await build($)).deny).toContain(GENERATE)
})

test('tools that only read are never refused, however stale the project', async ($, on) => {
  tuistProject(on)
  await editManifest($)
  expect((await callTool($, 'mcp__xcode__GetBuildLog')).deny).toBeUndefined()
  expect((await build($)).deny).toContain(GENERATE)
})

test('running the app through the Xcode MCP builds it first, so it is refused once too; a launch alone is not', async ($, on) => {
  tuistProject(on)
  await editManifest($)
  expect((await callTool($, 'mcp__xcode__RunProject')).deny).toContain(GENERATE)
  await editManifest($)
  expect((await callTool($, 'mcp__MobileBuildMCP__launch_app_sim')).deny).toBeUndefined()
})

// MARK: Two Tuist apps in one repository

/** Each app's manifests, by the file edited, as the CLI answers for them. */
const APPS = {
  a: { file: '/work/Repo/apps/a/Project.swift', app: 'apps/a', generate: 'tuist generate --no-open --path apps/a' },
  b: { file: '/work/Repo/apps/b/Project.swift', app: 'apps/b', generate: 'tuist generate --no-open --path apps/b' },
  bDependencies: { file: '/work/Repo/apps/b/Tuist/Package.swift', app: 'apps/b', generate: 'tuist install --path apps/b && tuist generate --no-open --path apps/b' },
} as const

/** A repository with two Tuist apps: the CLI names each app and its generate for an edit to its manifests. */
function twoApps(on: On): void {
  mock.store(on)
  stubCli(on, {
    project: args => {
      const edited = Object.values(APPS).find(app => args.includes(app.file))
      return { isGenerated: true, ...(edited ? { generate: edited.generate, app: edited.app } : {}) }
    },
  })
  on('tool.call', () => ({ result: {}, text: 'done' }))
}

const edit = (tool: Parameters<typeof callTool>[0], app: keyof typeof APPS) => callTool(tool, 'Edit', { file_path: APPS[app].file, old_string: 'a', new_string: 'b' })
const editBoth = async (tool: Parameters<typeof callTool>[0]) => {
  await edit(tool, 'a')
  await edit(tool, 'b')
}

test('with both apps edited, the refusal names each app\'s generate', async ($, on) => {
  twoApps(on)
  await editBoth($)
  const refused = await build($)
  expect(refused.deny).toContain(`\`${APPS.a.generate}\``)
  expect(refused.deny).toContain(`\`${APPS.b.generate}\``)
})

test('generating one app leaves the other\'s mark, and generating that one too lets the build run', async ($, on) => {
  twoApps(on)
  await editBoth($)
  await callTool($, 'Bash', { command: APPS.b.generate })
  const refused = await build($)
  expect(refused.deny).toContain(APPS.a.generate)
  expect(refused.deny).not.toContain(APPS.b.generate)
  await callTool($, 'Bash', { command: APPS.a.generate })
  expect((await build($)).deny).toBeUndefined()
})

test('both apps generated in one command clear both marks', async ($, on) => {
  twoApps(on)
  await editBoth($)
  await callTool($, 'Bash', { command: `${APPS.a.generate} && ${APPS.b.generate}` })
  expect((await build($)).deny).toBeUndefined()
})

test('a generate after a cd into one app clears that app\'s mark alone', async ($, on) => {
  twoApps(on)
  await editBoth($)
  await callTool($, 'Bash', { command: 'cd apps/a && tuist generate --no-open' })
  const refused = await build($)
  expect(refused.deny).toContain(APPS.b.generate)
  expect(refused.deny).not.toContain(APPS.a.generate)
})

test('an app named by its absolute path is the same app', async ($, on) => {
  twoApps(on)
  await edit($, 'a')
  await callTool($, 'Bash', { command: 'tuist generate --no-open --path /work/Repo/apps/a' })
  expect((await build($)).deny).toBeUndefined()
})

test('a generate that names no app may have run in any of them: it clears every mark', async ($, on) => {
  twoApps(on)
  await editBoth($)
  await callTool($, 'Bash', { command: 'tuist generate --no-open' })
  expect((await build($)).deny).toBeUndefined()
})

test('one app keeps one mark: after its dependencies change, the install stays in the command', async ($, on) => {
  twoApps(on)
  await edit($, 'bDependencies')
  await edit($, 'b')
  const refused = await build($)
  expect(refused.deny).toContain(`\`${APPS.bDependencies.generate}\``)
  expect(refused.deny).not.toContain(`\`${APPS.b.generate}\``)
})

// MARK: XcodeGen's included specs

test('an edit to a spec the XcodeGen spec includes marks the project, and other YAML only asks', async ($, on) => {
  mock.store(on)
  const included = '/work/App/targets/App.yml'
  const calls = stubCli(on, { project: args => ({ isGenerated: true, ...(args.includes(included) ? { generate: 'xcodegen generate', app: '' } : {}) }) })
  on('tool.call', () => ({ result: {}, text: 'done' }))
  await callTool($, 'Edit', { file_path: '/work/App/.github/workflows/ci.yml', old_string: 'a', new_string: 'b' })
  expect((await build($)).deny).toBeUndefined()
  await callTool($, 'Edit', { file_path: included, old_string: 'a', new_string: 'b' })
  expect((await build($)).deny).toContain('`xcodegen generate`')
  // The CLI decides for every YAML file: a spec can include another by any name.
  expect(calls.filter(call => call.args.includes('--manifest')).map(call => call.args.at(-1))).toEqual(['/work/App/.github/workflows/ci.yml', included])
})
