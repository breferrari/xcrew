import { expect, mock, test } from 'claude-code/testing'
import { callTool, stubCli } from './testing'

const TWO_DISPLAYS = '\n📷 Screenshot\n\nErrors (1):\n\n  ✗ Failed to capture screenshot: Cannot choose between 2 displays. Specify one with --display:\n\n❌ Failed to capture screenshot.\n'
const NOTE = 'xcrew: this simulator has more than one display'

/** A MobileBuildMCP tool that isn't a build or a test, failing: the CLI's notes for its error reach Claude. */
test("a failed MobileBuildMCP screenshot carries the CLI's note", async ($, on) => {
  mock.store(on)
  const calls = stubCli(on, { notes: (args, stdin) => (args.includes('--error') && stdin === TWO_DISPLAYS ? [NOTE] : []) })
  on('tool.call', () => ({ result: {}, text: TWO_DISPLAYS, isError: true }))
  const answered = await callTool($, 'mcp__MobileBuildMCP__screenshot', {})
  expect(answered.context).toContain(NOTE)
  expect(calls.filter(call => call.args[0] === 'note').map(call => call.args)).toEqual([['note', '--server', 'MobileBuildMCP', '--error']])
})

test('a MobileBuildMCP screenshot that worked asks the CLI nothing', async ($, on) => {
  mock.store(on)
  const calls = stubCli(on)
  on('tool.call', () => ({ result: {}, text: '\n📷 Screenshot\n\n✅ Captured.\n' }))
  await callTool($, 'mcp__plugin_xcrew_MobileBuildMCP__screenshot', {})
  expect(calls.filter(call => call.args[0] === 'note')).toEqual([])
})
