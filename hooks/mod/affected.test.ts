import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'
import { callTool, stubCli, type CliCall } from './testing'

const TOOL = 'mcp__xcrew__affected'

/** A session whose CLI answers `xcrew affected` with `answer`, or fails when it's an Error. Records the registered tools. */
function session(on: On, answer: unknown) {
  mock.store(on)
  const registered: { name: string; isDeferred?: unknown }[] = []
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => {
    registered.push({ name: e.name, isDeferred: e.isDeferred })
    return { value: { tool: `mcp__xcrew__${e.name}` } }
  })
  const calls: CliCall[] = stubCli(on, {
    affected: () => {
      if (answer instanceof Error) throw answer
      return answer
    },
  })
  on('tool.call', () => ({ result: {}, text: 'done' }))
  return { registered, calls }
}

const ask = async (tool: Engine, input: Record<string, unknown> = {}) => String((await callTool(tool, TOOL, input)).result ?? '')

test('Claude finds the affected tool behind ToolSearch, registered beside the ledger', async ($, on) => {
  const seen = session(on, {})
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  expect(seen.registered).toContainEqual({ name: 'affected', isDeferred: undefined })
})

test('a selection names the test targets and the -only-testing arguments that run them, with the base', async ($, on) => {
  session(on, { base: 'origin/main, from 0123456789ab', changed: ['Core/Store.swift'], selections: ['AppTests', 'CoreTests'] })
  const text = await ask($)
  expect(text).toContain('AppTests, CoreTests')
  expect(text).toContain('-only-testing:AppTests -only-testing:CoreTests')
  expect(text).toContain('origin/main, from 0123456789ab')
})

test('when everything must run, it says so with the reason', async ($, on) => {
  session(on, { base: 'origin/main, from 0123456789ab', changed: ['Package.resolved'], runAll: 'Package.resolved changes what the build does in a way this doesn\'t read' })
  const text = await ask($)
  expect(text).toMatch(/^Run the whole suite/)
  expect(text).toContain('Package.resolved changes what the build does')
})

test('when the CLI can\'t answer, the answer is to run everything', async ($, on) => {
  session(on, new Error('timed out'))
  expect(await ask($)).toMatch(/^Run the whole suite/)
})

test('a base Claude names is passed to the CLI', async ($, on) => {
  const seen = session(on, { base: 'release/2.0, from fedcba987654', changed: [], selections: [] })
  await ask($, { base: 'release/2.0' })
  expect(seen.calls.find(call => call.args[0] === 'affected')?.args).toEqual(['affected', '--base', 'release/2.0'])
})

test('changed files no test target covers are said to be changed, not missing', async ($, on) => {
  session(on, { base: 'origin/main, from 0123456789ab', changed: ['Widget/Timeline.swift'], selections: [] })
  const text = await ask($)
  expect(text).toContain('1 changed file')
  expect(text).not.toContain('Nothing has changed')
})

test('without a base the answer names none', async ($, on) => {
  session(on, { runAll: "this isn't a git repository, so the change can't be told apart" })
  expect(await ask($)).not.toContain('Compared with')
})

test('the CLI gets the time a first build needs', async ($, on) => {
  const seen = session(on, { base: 'b', changed: [], selections: [] })
  await ask($)
  expect(seen.calls.find(call => call.args[0] === 'affected')?.timeoutMs).toBe(120_000)
})

test('session start registers exactly the ledger, affected, look and evidence tools, once each', async ($, on) => {
  const seen = session(on, {})
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  expect(seen.registered).toEqual([{ name: 'ledger', isDeferred: undefined }, { name: 'affected', isDeferred: undefined }, { name: 'look', isDeferred: undefined }, { name: 'evidence', isDeferred: undefined }])
})
