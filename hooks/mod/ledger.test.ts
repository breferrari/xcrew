import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Report } from './cli'
import { callTool, runCommand, stubCli } from './testing'

const TEST = 'GreetingTests/testHello'
const FAILED: Partial<Report> = { ok: false, failures: [{ title: TEST, message: 'XCTAssertEqual failed: ("Hi") is not equal to ("Hello")', where: 'GreetingTests.swift:9', isTest: true }] }
const BUILD_FAILED: Partial<Report> = { ok: false, failures: [{ title: 'Greeting.swift:4', message: 'cannot find greet in scope', isTest: false }] }
const PASSED: Partial<Report> = { ok: true, detail: '12 passed' }
const DAY_MS = 24 * 60 * 60_000

/**
 * A project on `branch` (the CLI names it and the project's root), whose test runs report the next of `reports`. The
 * store starts with `stored`; registered tools are collected in `registered`.
 */
function project(on: On, reports: Partial<Report>[], options: { branch?: () => string | Error; stored?: Record<string, unknown> } = {}) {
  const clock = mock.clock(on, { now: Date.UTC(2026, 9, 30, 12, 0) })
  mock.store(on, options.stored ?? {})
  const registered: { name: string; isDeferred?: unknown }[] = []
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => {
    registered.push({ name: e.name, isDeferred: e.isDeferred })
    return { value: { tool: `mcp__xcrew__${e.name}` } }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  stubCli(on, {
    reports,
    project: args => {
      if (!args.includes('--branch')) return { isGenerated: false }
      const branch = options.branch?.() ?? 'feat/ledger'
      // A CLI that can't answer: the stand-in fails as a process that timed out would.
      if (branch instanceof Error) throw branch
      return { isGenerated: false, root: '/work/App', branch }
    },
  })
  on('tool.call', () => ({ result: {}, text: 'the server\'s result' }))
  return { clock, registered }
}

const LEDGER = 'mcp__xcrew__ledger'
const run = (tool: Engine, selection?: string) => callTool(tool, 'mcp__MobileBuildMCP__test_sim', selection ? { extraArgs: [`-only-testing:${selection}`] } : {})
const ledgerText = async (tool: Engine) => String((await callTool(tool, LEDGER)).result ?? '')

test('a test that fails and then passes in the same scope is listed red, then green, with both runs', async ($, on) => {
  const { clock } = project(on, [FAILED, PASSED])
  await run($, 'AppTests')
  await clock.advance(7 * 60_000)
  await run($, 'AppTests')
  const text = await ledgerText($)
  expect(text).toContain('Red, then green, on feat/ledger (1 test)')
  expect(text).toMatch(new RegExp(`- ${TEST}: red .* in test_sim › AppTests: XCTAssertEqual failed.*; green .* in test_sim › AppTests`))
  expect(text).not.toContain('Still red')
})

test('a pass of another selection never ran the test: it stays red', async ($, on) => {
  project(on, [FAILED, PASSED])
  await run($, 'AppTests')
  await run($, 'OtherTests')
  const text = await ledgerText($)
  expect(text).toContain(`Still red (1):\n- ${TEST}: red`)
  expect(text).not.toContain('Red, then green')
})

test('a pass of the whole suite on the same tool and scheme turns a selection\'s red green', async ($, on) => {
  project(on, [FAILED, PASSED])
  await run($, 'AppTests')
  await run($)
  expect(await ledgerText($)).toMatch(new RegExp(`- ${TEST}: red .* in test_sim › AppTests: .*; green .* in test_sim$`, 'm'))
})

test('a test that fails again after its green is red again, keeping its first red', async ($, on) => {
  const { clock } = project(on, [FAILED, PASSED, FAILED])
  await run($)
  const first = await ledgerText($)
  await clock.advance(60 * 60_000)
  await run($)
  await clock.advance(60 * 60_000)
  await run($)
  const text = await ledgerText($)
  expect(text).toContain('Still red (1)')
  expect(text).not.toContain('Red, then green')
  // The red is the first run's, an hour before either later one.
  expect(text).toBe(first)
})

test('a compile error never enters the ledger', async ($, on) => {
  project(on, [BUILD_FAILED, PASSED])
  await run($)
  await run($)
  expect(await ledgerText($)).toBe('No test has failed on feat/ledger yet.')
})

test('each branch keeps its own ledger, in the store, across sessions', async ($, on) => {
  let branch = 'feat/ledger'
  project(on, [FAILED], { branch: () => branch })
  await run($)
  branch = 'main'
  expect(await ledgerText($)).toBe('No test has failed on main yet.')
  branch = 'feat/ledger'
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  expect(await ledgerText($)).toContain(`Still red (1):\n- ${TEST}`)
})

test('a branch\'s ledger no run has written for two weeks is dropped', async ($, on) => {
  const old = { entries: [{ test: 'Old/testGone', red: { scope: 'test_sim', at: 0, message: 'gone' } }], updated: Date.UTC(2026, 9, 1) }
  const fresh = { entries: [{ test: 'New/testKept', red: { scope: 'test_sim', at: 0, message: 'kept' } }], updated: Date.UTC(2026, 9, 29) }
  let branch = 'feat/ledger'
  project(on, [FAILED], { branch: () => branch, stored: { 'ledger./work/App @ old': old, 'ledger./work/App @ fresh': fresh } })
  // Writing this branch's ledger drops the ones no run has written for two weeks.
  await run($)
  branch = 'old'
  expect(await ledgerText($)).toBe('No test has failed on old yet.')
  branch = 'fresh'
  expect(await ledgerText($)).toContain('New/testKept')
})

test('Claude reads the ledger through a tool registered behind ToolSearch, and /xcrew ledger shows the same text', async ($, on) => {
  const { registered } = project(on, [FAILED])
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  expect(registered).toEqual([{ name: 'ledger', isDeferred: undefined }])
  await run($)
  const shown = await runCommand($, 'xcrew', 'ledger')
  expect(shown.text).toBe(await ledgerText($))
  expect(shown.text).toContain(TEST)
})

test('without the CLI\'s answer the run goes on and nothing is written', async ($, on) => {
  let answers = false
  project(on, [FAILED], { branch: () => (answers ? 'feat/ledger' : new Error('timed out')) })
  const ran = await run($)
  expect(ran.deny).toBeUndefined()
  expect(ran.text).toBe('the server\'s result')
  answers = true
  expect(await ledgerText($)).toBe('No test has failed on feat/ledger yet.')
})

test('a day later the times say which day', async ($, on) => {
  const { clock } = project(on, [FAILED, PASSED])
  await run($)
  await clock.advance(DAY_MS)
  await run($)
  expect(await ledgerText($)).toMatch(/red Oct 30 \d\d:\d\d .*; green Oct 31 \d\d:\d\d/)
})
