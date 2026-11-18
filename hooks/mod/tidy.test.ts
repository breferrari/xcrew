import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import { callTool, stubCli } from './testing'

/** A session in a project whose runs all pass; what the stand-in CLI was asked is in `calls`. */
function project(on: On) {
  const clock = mock.clock(on, { now: Date.UTC(2026, 10, 18, 12, 0) })
  mock.store(on, {})
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => ({ value: { tool: `mcp__xcrew__${e.name}` } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  const calls = stubCli(on, { reports: [{ ok: true }], project: args => (args.includes('--branch') ? { isGenerated: false, root: '/work/App', branch: 'main' } : { isGenerated: false }) })
  on('tool.call', () => ({ result: {}, text: 'the server\'s result' }))
  return { calls, clock }
}

const tidied = (calls: { args: readonly string[] }[]) => calls.filter(call => call.args.join(' ') === 'tidy').length

test('each MobileBuildMCP test run asks the CLI to drop its finished test bundles', async ($, on) => {
  const { calls, clock } = project(on)
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  await clock.settle()
  expect(tidied(calls)).toBe(1)
  await callTool($, 'mcp__plugin_xcrew_MobileBuildMCP__test_sim')
  await clock.settle()
  expect(tidied(calls)).toBe(2)
})

test('a build, even one for testing, and an Xcode MCP test run leave the bundles alone', async ($, on) => {
  const { calls, clock } = project(on)
  await callTool($, 'mcp__MobileBuildMCP__build_sim', { buildForTesting: true })
  await callTool($, 'mcp__xcode__RunAllTests')
  await clock.settle()
  expect(tidied(calls)).toBe(0)
})
