import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Report } from './cli'
import { callTool, runCommand, stubCli, type CliCall } from './testing'

const TOOL = 'mcp__xcrew__evidence'
const NOW = Date.UTC(2026, 9, 30, 12, 0)
const BLOCK = '## Evidence\n\nTests this branch took from red to green:\n- `GreetingTests/testHello`: failed in `test_sim`, then passed in `test_sim`.\n\nImages to attach (for you, not the PR):\n- `GreetingTests/testHello`, images from its failing run:\n  /cache/images/run/GreetingTests/testHello/failure.png'
const ENTRY = { test: 'GreetingTests/testHello', red: { scope: 'test_sim', at: NOW - 3_600_000, message: 'XCTAssertEqual failed', bundle: '/runs/red.xcresult' }, failing: 'test_sim', green: { scope: 'test_sim', at: NOW - 60_000 }, last: NOW - 60_000 }

/** A session on feat/evidence in /work/App, whose store holds that branch's ledger and a test scope run here. */
function session(on: On, answer: string | Error | { stdout: string; stderr: string }, reports: Partial<Report>[] = [], options: { branch?: string | Error; ledger?: unknown } = {}) {
  mock.clock(on, { now: NOW })
  mock.store(on, {
    'ledger./work/App @ feat/evidence': options.ledger ?? { entries: [ENTRY], updated: NOW - 60_000 },
    'durations.test_sim': [80_000, 80_000],
    'updated.test_sim': NOW - 60_000,
    'tests.test_sim': 312,
    'where.test_sim': '/work/App',
    'durations.build_sim': [30_000],
    'updated.build_sim': NOW - 60_000,
    'where.build_sim': '/work/Other',
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.cwd', () => ({ value: '/work/App' }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => ({ value: { tool: `mcp__xcrew__${e.name}` } }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('session.surfaces', () => ({ value: ['terminal'] }))
  const calls: CliCall[] = stubCli(on, {
    evidence: () => answer,
    reports,
    project: args => {
      if (!args.includes('--branch')) return { isGenerated: false }
      if (options.branch instanceof Error) throw options.branch
      return { isGenerated: false, root: '/work/App', branch: options.branch ?? 'feat/evidence' }
    },
  })
  on('tool.call', () => ({ result: {}, text: 'done' }))
  return { calls }
}

const ask = async (tool: Engine) => String((await callTool(tool, TOOL)).result ?? '')

test('the CLI gets this branch\'s ledger and the run times of this folder, and Claude reads its answer as it is', async ($, on) => {
  const seen = session(on, BLOCK)
  expect(await ask($)).toBe(BLOCK)
  const sent = JSON.parse(seen.calls.find(call => call.args[0] === 'evidence')?.stdin ?? '{}') as { ledger?: unknown[]; times?: string[] }
  expect(sent.ledger).toEqual([ENTRY])
  // Run times as the card words them, of the scopes last run in this folder only.
  expect(sent.times).toEqual(['test_sim: usually 1:20, 312 tests'])
})

test('evidence asked right after a test run holds that run\'s red', async ($, on) => {
  const seen = session(on, BLOCK, [{ ok: false, failures: [{ title: 'GreetingTests/testNew', message: 'XCTFail', isTest: true }], bundle: '/runs/new.xcresult' }])
  await callTool($, 'mcp__MobileBuildMCP__test_sim', {})
  await ask($)
  const sent = JSON.parse(seen.calls.find(call => call.args[0] === 'evidence')?.stdin ?? '{}') as { ledger?: { test: string }[] }
  expect(sent.ledger?.map(entry => entry.test)).toContain('GreetingTests/testNew')
})

test('/xcrew evidence shows the person the same text', async ($, on) => {
  session(on, BLOCK)
  expect((await runCommand($, 'xcrew', 'evidence')).text).toBe(BLOCK)
})

test('when the CLI can\'t run, Claude is told so', async ($, on) => {
  session(on, new Error('timed out'))
  expect(await ask($)).toStartWith("xcrew evidence couldn't run: ")
})

test('when the branch can\'t be named, the evidence says its ledger couldn\'t be read rather than that nothing failed', async ($, on) => {
  const seen = session(on, BLOCK, [], { branch: new Error('timed out') })
  expect(await ask($)).toStartWith("The evidence couldn't be read: xcrew's CLI didn't say which branch is checked out")
  expect(seen.calls.some(call => call.args[0] === 'evidence')).toBe(false)
})

test('a red-to-green test no run has written for weeks is still evidence, as the ledger still lists it', async ($, on) => {
  const old = { ...ENTRY, red: { ...ENTRY.red, at: NOW - 20 * 24 * 3_600_000 }, green: { scope: 'test_sim', at: NOW - 15 * 24 * 3_600_000 }, last: NOW - 15 * 24 * 3_600_000 }
  const seen = session(on, BLOCK, [], { ledger: { entries: [old], updated: NOW - 15 * 24 * 3_600_000 } })
  await ask($)
  const sent = JSON.parse(seen.calls.find(call => call.args[0] === 'evidence')?.stdin ?? '{}') as { ledger?: unknown[] }
  expect(sent.ledger).toEqual([old])
})

test('the CLI has as long as reading ten result bundles takes', async ($, on) => {
  const seen = session(on, BLOCK)
  await ask($)
  expect(seen.calls.find(call => call.args[0] === 'evidence')?.timeoutMs).toBe(300_000)
})

test('only what the CLI prints for the pull request reaches Claude: its warnings on stderr stay out', async ($, on) => {
  session(on, { stdout: BLOCK, stderr: 'xcrew: building the CLI for this version (once, 10 to 20 s)…\n/Users/someone/.cache/build.log' })
  expect(await ask($)).toBe(BLOCK)
})
