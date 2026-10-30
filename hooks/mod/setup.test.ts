import { expect, mock, test } from 'claude-code/testing'
import type { On, ToolCallResult } from 'claude-code'
import { callTool, stubCli, type CliCall } from './testing'

/** The CLI's line, whatever it says: the mod passes it on as given. */
const NUDGE = 'offer setup, as the CLI words it'

/** A project whose config has a scheme to build with or not; beneath the mod, every tool answers. */
function project(on: On, hasProfiles: boolean): CliCall[] {
  mock.store(on)
  const calls = stubCli(on, { project: args => (args.includes('--profiles') && !hasProfiles ? { isGenerated: false, setup: NUDGE } : { isGenerated: false }) })
  on('tool.call', () => ({ result: {}, text: 'done' }))
  return calls
}

const contextOf = (result: ToolCallResult) => (result.context ?? []).join('\n')

test('the first MobileBuildMCP build without a profile says to offer setup, and only the first', async ($, on) => {
  project(on, false)
  expect(contextOf(await callTool($, 'mcp__plugin_xcrew_MobileBuildMCP__build_sim'))).toContain(NUDGE)
  expect(contextOf(await callTool($, 'mcp__plugin_xcrew_MobileBuildMCP__test_sim'))).not.toContain(NUDGE)
})

test('a test run under the server\'s own registration says it too', async ($, on) => {
  project(on, false)
  expect(contextOf(await callTool($, 'mcp__MobileBuildMCP__test_sim'))).toContain(NUDGE)
})

test('with a profile that names a scheme, a build says nothing of setup', async ($, on) => {
  project(on, true)
  expect(contextOf(await callTool($, 'mcp__plugin_xcrew_MobileBuildMCP__build_sim'))).not.toContain(NUDGE)
})

test('the Xcode MCP\'s builds and MobileBuildMCP\'s reads ask nothing', async ($, on) => {
  const calls = project(on, false)
  expect(contextOf(await callTool($, 'mcp__plugin_xcrew_xcode__BuildProject'))).not.toContain(NUDGE)
  expect(contextOf(await callTool($, 'mcp__plugin_xcrew_MobileBuildMCP__list_schemes'))).not.toContain(NUDGE)
  expect(calls.filter(call => call.args.includes('--profiles'))).toHaveLength(0)
})

test('builds started together say it once', async ($, on) => {
  project(on, false)
  const results = await Promise.all([callTool($, 'mcp__plugin_xcrew_MobileBuildMCP__build_sim'), callTool($, 'mcp__plugin_xcrew_MobileBuildMCP__test_sim')])
  expect(results.filter(result => contextOf(result).includes(NUDGE))).toHaveLength(1)
})
