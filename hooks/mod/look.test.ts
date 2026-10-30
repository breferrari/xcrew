import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'
import { callTool, stubCli, type CliCall } from './testing'

const TOOL = 'mcp__xcrew__look'

/** A session whose CLI prints `answer` for `xcrew look`, or fails when it's an Error. Records the registered tools. */
function session(on: On, answer: string | Error) {
  mock.store(on)
  const registered: { name: string; isDeferred?: unknown }[] = []
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => {
    registered.push({ name: e.name, isDeferred: e.isDeferred })
    return { value: { tool: `mcp__xcrew__${e.name}` } }
  })
  const calls: CliCall[] = stubCli(on, { look: () => answer })
  on('tool.call', () => ({ result: {}, text: 'done' }))
  return { registered, calls }
}

const ask = async (tool: Engine, input: Record<string, unknown> = {}) => String((await callTool(tool, TOOL, input)).result ?? '')

test('Claude finds the look tool behind ToolSearch', async ($, on) => {
  const seen = session(on, '')
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  expect(seen.registered).toContainEqual({ name: 'look', isDeferred: undefined })
})

test('Claude reads what the CLI says, as it says it', async ($, on) => {
  session(on, 'xcrew look: AppUITests/testLogin, in Run.xcresult\n  iPhone 17, iOS 27.2\n    ✗ Failed to tap "Login" Button\n    screen: /cache/images/Run/AppUITests/testLogin/screen.png\n')
  expect(await ask($)).toBe('xcrew look: AppUITests/testLogin, in Run.xcresult\n  iPhone 17, iOS 27.2\n    ✗ Failed to tap "Login" Button\n    screen: /cache/images/Run/AppUITests/testLogin/screen.png')
})

test('a test and a bundle Claude names are passed to the CLI', async ($, on) => {
  const seen = session(on, '')
  await ask($, { test: 'AppUITests/testLogin', bundle: '/runs/Run.xcresult' })
  expect(seen.calls.find(call => call.args[0] === 'look')?.args).toEqual(['look', 'AppUITests/testLogin', '--bundle', '/runs/Run.xcresult'])
})

test('without either, the CLI picks the newest run', async ($, on) => {
  const seen = session(on, '')
  await ask($)
  expect(seen.calls.find(call => call.args[0] === 'look')?.args).toEqual(['look'])
})

test('when the CLI can\'t run, Claude is told so', async ($, on) => {
  session(on, new Error('timed out'))
  expect(await ask($)).toStartWith("xcrew look couldn't run: ")
})
