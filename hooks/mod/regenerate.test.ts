import { expect, mock, test } from 'claude-code/testing'
import type { On, ToolCallResult } from 'claude-code'
import { callTool, stubCli, type CliCall } from './testing'

const GENERATE = 'tuist generate --no-open --path ios'
const MANIFEST = '/work/App/ios/Project.swift'

/**
 * A Tuist project whose CLI names `GENERATE` for an edit to `MANIFEST` and nothing for any other file. Beneath the
 * mod, every tool answers, and a Bash command fails when `failing` holds it.
 */
function tuistProject(on: On, failing: string[] = []): CliCall[] {
  mock.store(on)
  const calls = stubCli(on, { project: args => ({ isGenerated: true, ...(args.includes(MANIFEST) ? { generate: GENERATE } : {}) }) })
  on('tool.call', (_, e) => {
    if (e.tool === 'Bash' && failing.includes(e.command)) return { isError: true, result: 'Exit code 1', text: 'Exit code 1' }
    return { result: {}, text: 'done' }
  })
  return calls
}

const editManifest = (tool: Parameters<typeof callTool>[0]) => callTool(tool, 'Edit', { file_path: MANIFEST, old_string: 'a', new_string: 'b' })
const build = (tool: Parameters<typeof callTool>[0], name = 'mcp__plugin_xcrew_MobileBuildMCP__build_sim') => callTool(tool, name)
const contextOf = (result: ToolCallResult) => (result.context ?? []).join('\n')

test('after a manifest edit the first build is refused with the command that regenerates the project', async ($, on) => {
  tuistProject(on)
  await editManifest($)
  const refused = await build($)
  expect(refused.deny).toContain(`\`${GENERATE}\``)
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
  stubCli(on, { project: () => ({ isGenerated: true, generate: GENERATE }) })
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
