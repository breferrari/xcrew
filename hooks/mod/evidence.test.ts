import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'
import { callTool, runCommand, stubCli, type CliCall } from './testing'

const TOOL = 'mcp__xcrew__evidence'
const NOW = Date.UTC(2026, 9, 30, 12, 0)
const BLOCK = '## Evidence\n\nTests this branch took from red to green:\n- `GreetingTests/testHello`: failed in `test_sim`, then passed in `test_sim`.\n\nImages to attach (for you, not the PR):\n- `GreetingTests/testHello`, images from its failing run:\n  /cache/images/run/GreetingTests/testHello/failure.png'
const ENTRY = { test: 'GreetingTests/testHello', red: { scope: 'test_sim', at: NOW - 3_600_000, message: 'XCTAssertEqual failed', bundle: '/runs/red.xcresult' }, failing: 'test_sim', green: { scope: 'test_sim', at: NOW - 60_000 }, last: NOW - 60_000 }

/** A session on feat/evidence in /work/App, whose store holds that branch's ledger and a test scope run here. */
function session(on: On, answer: string | Error) {
  mock.clock(on, { now: NOW })
  mock.store(on, {
    'ledger./work/App @ feat/evidence': { entries: [ENTRY], updated: NOW - 60_000 },
    'durations.test_sim': [80_000, 80_000],
    'updated.test_sim': NOW - 60_000,
    'tests.test_sim': 312,
    'where.test_sim': '/work/App',
    'durations.build_sim': [30_000],
    'updated.build_sim': NOW - 60_000,
    'where.build_sim': '/work/Other',
  })
  const registered: { name: string; isDeferred?: unknown }[] = []
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.cwd', () => ({ value: '/work/App' }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => {
    registered.push({ name: e.name, isDeferred: e.isDeferred })
    return { value: { tool: `mcp__xcrew__${e.name}` } }
  })
  const calls: CliCall[] = stubCli(on, {
    evidence: () => answer,
    project: args => (args.includes('--branch') ? { isGenerated: false, root: '/work/App', branch: 'feat/evidence' } : { isGenerated: false }),
  })
  on('tool.call', () => ({ result: {}, text: 'done' }))
  return { registered, calls }
}

const ask = async (tool: Engine) => String((await callTool(tool, TOOL)).result ?? '')

test('Claude finds the evidence tool behind ToolSearch', async ($, on) => {
  const seen = session(on, '')
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  expect(seen.registered).toContainEqual({ name: 'evidence', isDeferred: undefined })
})

test('the CLI gets this branch\'s ledger and the run times of this folder, and Claude reads its answer as it is', async ($, on) => {
  const seen = session(on, BLOCK)
  expect(await ask($)).toBe(BLOCK)
  const sent = JSON.parse(seen.calls.find(call => call.args[0] === 'evidence')?.stdin ?? '{}') as { ledger?: unknown[]; times?: string[] }
  expect(sent.ledger).toEqual([ENTRY])
  // Run times as the card words them, of the scopes last run in this folder only.
  expect(sent.times).toEqual(['test_sim: usually 1:20, 312 tests'])
})

test('/xcrew evidence shows the person the same text', async ($, on) => {
  session(on, BLOCK)
  expect((await runCommand($, 'xcrew', 'evidence')).text).toBe(BLOCK)
})

test('when the CLI can\'t run, Claude is told so', async ($, on) => {
  session(on, new Error('timed out'))
  expect(await ask($)).toStartWith("xcrew evidence couldn't run: ")
})
