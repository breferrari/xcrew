import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Report } from './cli'
import { failedKey, historyKey, scopeKey, testsKey, updatedKey } from './timing'
import { callTool, mapStore, runCommand, stubCli } from './testing'

const NOW = Date.UTC(2026, 9, 30, 12, 0)
const DAY = 24 * 60 * 60_000

/**
 * A session whose project's root is `root`, as `xcrew project --branch` answers, its MobileBuildMCP profile building
 * `scheme` (none: no scheme to build), each build taking the next of `took`, its outcome the next of `reports`.
 */
function session(on: On, { root = '/work/App', scheme, took = [], reports = [{ ok: true }], stored = {}, rootFails = 0, cwd = root }: { root?: string; scheme?: string; took?: number[]; reports?: Partial<Report>[]; stored?: Record<string, unknown>; rootFails?: number; cwd?: string } = {}) {
  const clock = mock.clock(on, { now: NOW })
  const store = mapStore(on, stored)
  const toasts: string[] = []
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => ({ value: { tool: `mcp__xcrew__${e.name}` } }))
  on('session.surfaces', () => ({ value: ['vscode'] }))
  on('session.cwd', () => ({ value: cwd }))
  on('ui.toast', (_, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  on('ui.status', () => ({ value: undefined }))
  on('ui.notify', () => ({ value: { isSent: true, channel: 'terminal_bell' } }))
  const cli = stubCli(on, {
    // The first `rootFails` reads of the root get no answer naming one, as a CLI still building answers.
    project: args => ({ isGenerated: false, ...(args.includes('--branch') && rootFails-- <= 0 ? { root, branch: 'main' } : {}), ...(args.includes('--profiles') && scheme ? { scheme } : {}) }),
    reports,
  })
  on('tool.call', async () => {
    await clock.advance(took.shift() ?? 0)
    return { result: {}, text: 'done' }
  })
  return { clock, store, toasts, cli }
}

async function start($: Engine, clock: { settle: () => Promise<void> }, root = '/work/App') {
  await $.session.start({ cwd: root, surface: 'terminal', isInteractive: true })
  await clock.settle()
}

/** Two checkouts with a scheme of one name measure their runs apart: each is its own repository's. */
test("another repository's runs of the same scheme are no usual time here", async ($, on) => {
  const stored = { [historyKey(scopeKey('/work/Other', 'BuildProject'))]: [600_000], [updatedKey(scopeKey('/work/Other', 'BuildProject'))]: NOW }
  const { toasts, clock } = session(on, { took: [60_000], stored })
  await start($, clock)
  await callTool($, 'mcp__xcode__BuildProject')
  expect(toasts.at(-1)).toBe('✓ BuildProject · 1:00')
})

/** A failed run ends early: its time is kept apart and never taken as the usual one. */
test("a failed run's time is kept apart from the usual time", async ($, on) => {
  const { toasts, clock, store } = session(on, { took: [60_000, 5_000, 80_000], reports: [{ ok: true }, { ok: false }, { ok: true }] })
  await start($, clock)
  for (let run = 0; run < 3; run += 1) await callTool($, 'mcp__xcode__BuildProject')
  expect(toasts.at(-1)).toBe('✓ BuildProject · 1:20 (avg 1:00)')
  expect(store.get(historyKey(scopeKey('/work/App', 'BuildProject')))).toEqual([60_000, 80_000])
  expect(store.get(failedKey(scopeKey('/work/App', 'BuildProject')))).toEqual([5_000])
  expect((await runCommand($, 'xcrew', 'history')).text).toContain('1 failed run, 0:05')
})

/** A MobileBuildMCP call that names no scheme builds the profile's: its runs are kept under that scheme. */
test("a run whose call names no scheme is kept under the profile's", async ($, on) => {
  const { clock, store } = session(on, { scheme: 'App', took: [30_000] })
  await start($, clock)
  await callTool($, 'mcp__MobileBuildMCP__build_sim')
  expect(store.get(historyKey(scopeKey('/work/App', 'build_sim · App')))).toEqual([30_000])
})

/** With no scheme the run's can be named, it's timed and shown, and kept under no key without one. */
test('a run whose scheme no one can name keeps no history', async ($, on) => {
  const { clock, store, toasts } = session(on, { took: [30_000] })
  await start($, clock)
  await callTool($, 'mcp__MobileBuildMCP__build_sim')
  expect(toasts.at(-1)).toBe('✓ build_sim · 0:30')
  expect([...store.keys()].filter(key => /^(durations|failed|updated|tests)\./.test(key))).toEqual([])
})

/** At the start of a session, the history is left with this version's keys, each holding runs a run wrote lately. */
test("a session's start drops old-format, stale and empty history", async ($, on) => {
  const kept = scopeKey('/work/App', 'build_sim · App'), stale = scopeKey('/work/App', 'test_sim · App'), empty = scopeKey('/work/App', 'test_sim · App › AppTests')
  const stored = {
    'durations.build_sim': [10_000], 'updated.build_sim': NOW, 'where.build_sim': '/work/App', 'tests.build_sim': 3,
    [historyKey(kept)]: [30_000], [updatedKey(kept)]: NOW - DAY,
    [historyKey(stale)]: [90_000], [updatedKey(stale)]: NOW - 15 * DAY, [testsKey(stale)]: 959,
    [historyKey(empty)]: [], [updatedKey(empty)]: NOW - DAY,
  }
  const { clock, store } = session(on, { stored })
  await start($, clock)
  expect([...store.keys()].sort()).toEqual([historyKey(kept), updatedKey(kept)].sort())
})

/** A failed run on a scope no run has updated for weeks starts it over: the old runs don't come back as usual times. */
test('a failed run after weeks away brings no old runs back', async ($, on) => {
  const key = scopeKey('/work/App', 'BuildProject')
  const stored = { [historyKey(key)]: [600_000], [updatedKey(key)]: NOW - 20 * DAY, [failedKey(key)]: [1_000] }
  // No session start prunes it first, as in a session that began before the scope went stale.
  const { toasts, store } = session(on, { took: [5_000, 60_000], reports: [{ ok: false }, { ok: true }], stored })
  await callTool($, 'mcp__xcode__BuildProject')
  await callTool($, 'mcp__xcode__BuildProject')
  expect(toasts.at(-1)).toBe('✓ BuildProject · 1:00')
  expect(store.get(failedKey(key))).toEqual([5_000])
})

/** A failed test run stops early: its count is no total for the next run's `testing 300 of 959`. */
test("a failed test run's count isn't kept as the total", async ($, on) => {
  const { clock, store } = session(on, { scheme: 'App', took: [5_000], reports: [{ ok: false, tests: 40 }] })
  await start($, clock)
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  expect(store.get(testsKey(scopeKey('/work/App', 'test_sim · App')))).toBeUndefined()
})

/** A root the CLI couldn't name yet, as while it builds, is asked again: the session's runs aren't kept under its folder for good. */
test('a root not named yet is asked for again', async ($, on) => {
  const { store } = session(on, { root: '/work/App', cwd: '/work/App/ios', took: [10_000, 20_000], rootFails: 1 })
  await callTool($, 'mcp__xcode__BuildProject')
  await callTool($, 'mcp__xcode__BuildProject')
  expect(store.get(historyKey(scopeKey('/work/App', 'BuildProject')))).toEqual([20_000])
})

/** A scope whose every run failed is still in the history, with no usual time. */
test('/xcrew history shows a scope whose runs all failed', async ($, on) => {
  const { clock } = session(on, { took: [5_000], reports: [{ ok: false }] })
  await start($, clock)
  await callTool($, 'mcp__xcode__BuildProject')
  expect((await runCommand($, 'xcrew', 'history')).text).toContain('no passing run yet · 1 failed run, 0:05  BuildProject')
})
