import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'
import { callTool, stubCli } from './testing'

const NOW = Date.UTC(2026, 9, 30, 12, 0)
const CARD = 'xcrewProjectCard'

/** What earlier sessions stored: durations, when each was last updated, test totals, and the folder each last ran in, by run scope. */
function runs(scopes: Record<string, { runs: number[]; tests?: number }>, folder = '/work/App'): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(scopes).flatMap(([scope, { runs, tests }]) => [
      [`durations.${scope}`, runs],
      [`updated.${scope}`, NOW - 60_000],
      [`where.${scope}`, folder],
      ...(tests === undefined ? [] : [[`tests.${scope}`, tests]]),
    ]),
  )
}

/** A red test on `feat/card`, as A's ledger keeps it. */
function ledger(tests: { test: string; failing: string }[]): Record<string, unknown> {
  const entries = tests.map(({ test, failing }) => ({ test, red: { scope: failing, at: NOW - 60_000, message: 'failed' }, failing, last: NOW - 60_000 }))
  return { 'ledger./work/App @ feat/card': { entries, updated: NOW - 60_000 } }
}

/** A session in a project on `feat/card` whose store holds `stored`; the engine composes one section of its own. */
function session(on: On, stored: Record<string, unknown> | 'unavailable', options: { branch?: () => Promise<string> } = {}) {
  const clock = mock.clock(on, { now: NOW })
  if (stored !== 'unavailable') mock.store(on, stored)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => ({ value: { tool: `mcp__xcrew__${e.name}` } }))
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('session.cwd', () => ({ value: '/work/App' }))
  on('prompt.context', (_, e) => ({ blocks: e.blocks }))
  stubCli(on, {
    project: async args => ({ isGenerated: false, ...(args.includes('--branch') ? { root: '/work/App', branch: await (options.branch?.() ?? Promise.resolve('feat/card')) } : {}) }),
    reports: [{ ok: true }],
  })
  on('tool.call', () => ({ result: {}, text: 'done' }))
  return clock
}

async function start(tool: Engine, clock: { settle: () => Promise<void> }): Promise<void> {
  await tool.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
}

/** The card, as the context of the conversation's first message carries it, after the engine's own blocks. */
async function card(tool: Engine): Promise<string | undefined> {
  const blocks = (await tool.prompt.context({ blocks: [{ name: 'currentDate', text: '2026-10-30' }] })).blocks
  expect(blocks[0]?.name).toBe('currentDate')
  return blocks.find(block => block.name === CARD)?.text
}

test('the card gives the usual durations, slowest first, the red tests, and the selections when a full run is slow', async ($, on) => {
  const clock = session(on, {
    ...runs({ 'test_sim · App': { runs: [190_000, 186_000], tests: 959 }, 'build_sim · App': { runs: [45_000] }, 'test_sim · App › AppTests': { runs: [30_000], tests: 120 } }),
    ...ledger([{ test: 'GreetingTests/testHello', failing: 'test_sim · App › AppTests' }]),
  })
  await start($, clock)
  const text = (await card($)) ?? ''
  const lines = text.split('\n')
  expect(lines.findIndex(line => line.includes('test_sim · App:'))).toBeLessThan(lines.findIndex(line => line.includes('build_sim · App:')))
  expect(text).toContain('test_sim · App: usually 3:08, 959 tests')
  expect(text).toContain('build_sim · App: usually 0:45')
  expect(text).toContain('Still red on feat/card: GreetingTests/testHello (test_sim · App › AppTests)')
  expect(text).toMatch(/A full test_sim · App run takes 3:08; .*test_sim · App › AppTests/)
})

test('a full run under two minutes gets no hint', async ($, on) => {
  const clock = session(on, runs({ 'test_sim · App': { runs: [60_000], tests: 959 }, 'test_sim · App › AppTests': { runs: [20_000], tests: 120 } }))
  await start($, clock)
  expect(await card($)).not.toMatch(/A full/)
})

test('with nothing stored there is no card', async ($, on) => {
  const clock = session(on, {})
  await start($, clock)
  expect(await card($)).toBeUndefined()
})

test('a new session, as /clear starts, builds the card afresh', async ($, on) => {
  const clock = session(on, runs({ 'build_sim · App': { runs: [45_000] } }))
  await start($, clock)
  await callTool($, 'mcp__MobileBuildMCP__test_sim', { scheme: 'App' })
  await start($, clock)
  expect(await card($)).toContain('test_sim · App: usually')
})

test('without a store the session starts and there is no card', async ($, on) => {
  const clock = session(on, 'unavailable')
  await start($, clock)
  expect(await card($)).toBeUndefined()
})

test('however much is stored, the card stays within ten lines and 800 characters, the rest counted', async ($, on) => {
  const scopes = Object.fromEntries(Array.from({ length: 30 }, (_, index) => [`test_sim · Module${index}WithAVeryLongSchemeName › Module${index}Tests/SomeSuite`, { runs: [200_000 + index * 1000], tests: 100 }]))
  const reds = Array.from({ length: 40 }, (_, index) => ({ test: `Module${index}Tests/SomeVeryLongTestCaseName/test_somethingQuiteDescriptive_${index}`, failing: `test_sim · Module${index}WithAVeryLongSchemeName` }))
  const clock = session(on, { ...runs(scopes), ...ledger(reds) })
  await start($, clock)
  const text = (await card($)) ?? ''
  expect(text.split('\n').length).toBeLessThanOrEqual(10)
  expect(text.length).toBeLessThanOrEqual(800)
  expect(text).toMatch(/\+\d+ more/)
})

test('durations a run in another project left are no notes on this one', async ($, on) => {
  const clock = session(on, { ...runs({ 'build_sim · App': { runs: [45_000] } }), ...runs({ 'test_sim · Shop': { runs: [250_000], tests: 1200 } }, '/work/Shop') })
  await start($, clock)
  const text = (await card($)) ?? ''
  expect(text).toContain('build_sim · App')
  expect(text).not.toContain('Shop')
})

test('red tests no run has written within the history\'s time are no longer news', async ($, on) => {
  const old = NOW - 30 * 24 * 60 * 60_000
  const stale = { entries: [{ test: 'Old/testGone', red: { scope: 'test_sim', at: old, message: 'x' }, failing: 'test_sim', last: old }], updated: old }
  const clock = session(on, { ...runs({ 'build_sim · App': { runs: [45_000] } }), 'ledger./work/App @ feat/card': stale })
  await start($, clock)
  expect(await card($)).not.toContain('Old/testGone')
})

test('a long list says how many it left out, durations and red tests alike', async ($, on) => {
  const scopes = Object.fromEntries(Array.from({ length: 8 }, (_, index) => [`build_sim · Module${index}`, { runs: [10_000 + index] }]))
  const reds = Array.from({ length: 12 }, (_, index) => ({ test: `Module${index}Tests/SomeVeryLongTestCaseName/test_somethingQuiteDescriptive_${index}`, failing: `test_sim · Module${index}WithAVeryLongSchemeName` }))
  const clock = session(on, { ...runs(scopes), ...ledger(reds) })
  await start($, clock)
  const text = (await card($)) ?? ''
  expect(text).toMatch(/Still red on feat\/card: .* \+\d+ more$/m)
  expect(text).toContain('+3 more')
})

test('a card the CLI is too slow to finish stays out of that conversation', async ($, on) => {
  const clock = session(on, runs({ 'build_sim · App': { runs: [45_000] } }), { branch: () => new Promise(() => {}) })
  await start($, clock)
  const read = card($)
  await clock.advance(1_500)
  expect(await read).toBeUndefined()
})

test('a flaky red test is marked so on the card', async ($, on) => {
  const entries = [{ test: 'GreetingTests/testHello', red: { scope: 'test_sim', at: NOW - 60_000, message: 'failed' }, failing: 'test_sim', last: NOW - 60_000, flaky: { failed: 2, runs: 5 } }]
  const clock = session(on, { 'ledger./work/App @ feat/card': { entries, updated: NOW - 60_000 } })
  await start($, clock)
  expect(await card($)).toContain('GreetingTests/testHello (flaky: failed 2 of 5 runs) (test_sim)')
})
