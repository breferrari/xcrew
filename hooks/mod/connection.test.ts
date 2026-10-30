import { expect, mock, test } from 'claude-code/testing'
import { callTool, stubCli } from './testing'

const CLOSED = 'MCP error -32000: Connection closed'
const NOTE = "xcrew: the Xcode MCP's connection closed, as it does when the selected Xcode changes during a session; /mcp → Reconnect restarts it."

/** An Xcode MCP tool that isn't a build or a test, failing as its connection closed: the CLI's note reaches Claude. */
test("an Xcode MCP call whose connection closed carries the CLI's note", async ($, on) => {
  mock.store(on)
  const calls = stubCli(on, { notes: (args, stdin) => (args.includes('--error') && stdin === CLOSED ? [NOTE] : []) })
  on('tool.call', () => ({ result: {}, text: CLOSED, isError: true }))
  const answered = await callTool($, 'mcp__xcode__XcodeRead', { filePath: 'App/ContentView.swift' })
  expect(answered.context).toContain(NOTE)
  expect(calls.filter(call => call.args[0] === 'note').map(call => call.args)).toEqual([['note', '--server', 'xcode', '--error']])
})

/** A call that worked, or another server's, asks nothing. */
test('an Xcode MCP call that worked asks the CLI nothing', async ($, on) => {
  mock.store(on)
  const calls = stubCli(on)
  on('tool.call', () => ({ result: {}, text: 'the file' }))
  await callTool($, 'mcp__xcode__XcodeRead', { filePath: 'App/ContentView.swift' })
  expect(calls.filter(call => call.args[0] === 'note')).toEqual([])
})

/** MobileBuildMCP proxies an Xcode MCP tool through a bridge of its own, which reconnecting the plugin's server doesn't restart. */
test('a proxied Xcode MCP tool whose connection closed asks the CLI nothing', async ($, on) => {
  mock.store(on)
  const calls = stubCli(on, { notes: () => [NOTE] })
  on('tool.call', () => ({ result: {}, text: CLOSED, isError: true }))
  const answered = await callTool($, 'mcp__MobileBuildMCP__xcode_tools_XcodeRead', { filePath: 'App/ContentView.swift' })
  expect(answered.context ?? []).not.toContain(NOTE)
  expect(calls.filter(call => call.args[0] === 'note')).toEqual([])
})
