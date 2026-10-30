import { expect, mock, test } from 'claude-code/testing'
import type { On, ToolCallResult } from 'claude-code'
import { callTool, stubCli, type CliCall } from './testing'

const NUDGE = 'No MobileBuildMCP profile for this project yet: `/xcrew:setup` writes them once, from the project\'s schemes and simulators. Offer it to the person.'

/** A project whose config has a profile with a scheme or not; beneath the mod, every tool answers. */
function project(on: On, hasProfiles: boolean): CliCall[] {
  mock.store(on)
  const calls = stubCli(on, { project: { isGenerated: false, hasProfiles } })
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
  expect(calls.filter(call => call.args.includes('--setup'))).toHaveLength(0)
})
