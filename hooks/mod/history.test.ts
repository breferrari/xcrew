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
function session(
  on: On,
  { root = '/work/App', scheme, took = [], reports = [{ ok: true }], stored = {}, rootFails = 0, cwd = root, profiles = {}, xcode, xcodeServerAfter = 0, xcodeHeld, selections = [], outputs = {}, logScheme, gone }: {
    root?: string; scheme?: string; took?: number[]; reports?: Partial<Report>[]; stored?: Record<string, unknown>; rootFails?: number; cwd?: string
    /** What `xcrew gone` answers for the folders it's asked about; no answer when undefined. */
    gone?: (folders: readonly string[]) => unknown
    /** The scheme the run's log names once `xcrew phase` finds it; no log when undefined. */
    logScheme?: string
    /** Each profile's scheme, as `--profiles --profile <name>` answers it. */
    profiles?: Record<string, string>
    /** What `--xcode` answers when Xcode hosts MobileBuildMCP's server: the selection at its start. */
    xcode?: { activeProfile: string; scheme: string; follows: boolean }
    /** How many `--xcode` asks find no server before one is found; what holds each answer back until it resolves. */
    xcodeServerAfter?: number
    xcodeHeld?: Promise<void>
    /** What each `--xcuserstate` read answers in turn, the last one again after. */
    selections?: string[]
    /** What a tool answers, by its name. */
    outputs?: Record<string, string>
  } = {},
) {
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
    project: async args => {
      if (args.includes('--xcode') && xcodeHeld) await xcodeHeld
      const server = !args.includes('--xcode') || xcodeServerAfter-- <= 0
      const profile = args.includes('--profile') ? profiles[args[args.indexOf('--profile') + 1] ?? ''] : scheme
      const selected = args.includes('--xcuserstate') ? (selections.length > 1 ? selections.shift() : selections[0]) : undefined
      return {
        isGenerated: false,
        ...(args.includes('--branch') && rootFails-- <= 0 ? { root, branch: 'main' } : {}),
        ...(args.includes('--profiles') && profile ? { scheme: profile } : {}),
        ...(args.includes('--xcode') && server ? { xcodeHostsServer: xcode !== undefined } : {}),
        ...(args.includes('--xcode') && server && xcode ? { activeProfile: xcode.activeProfile, xcodeState: '/work/App/App.xcworkspace/xcuserdata/someone.xcuserdatad/UserInterfaceState.xcuserstate', xcodeScheme: xcode.scheme, followsXcode: xcode.follows } : {}),
        ...(selected ? { xcodeScheme: selected } : {}),
      }
    },
    reports,
    phase: () => (logScheme === undefined ? {} : { log: '/logs/test_sim_1.log', scheme: logScheme }),
    ...(gone ? { gone } : {}),
  })
  on('tool.call', async (_, e) => {
    const output = outputs[e.tool.split('__').pop() ?? '']
    if (output !== undefined) return { result: {}, text: output }
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

/** The run's log names what it built, which keys its history, whatever scheme was worked out before it appeared. */
test('a run is kept under the scheme its log names, not the one worked out', async ($, on) => {
  const { clock, store } = session(on, { scheme: 'App', logScheme: 'Feature', took: [30_000] })
  await start($, clock)
  await callTool($, 'mcp__MobileBuildMCP__build_sim')
  expect(store.get(historyKey(scopeKey('/work/App', 'build_sim · Feature')))).toEqual([30_000])
  expect(store.get(historyKey(scopeKey('/work/App', 'build_sim · App')))).toBeUndefined()
})

/** A run that ends before the ticker reads its log has the report find that log, and is kept under the scheme it names. */
test('a run too fast for the ticker is kept under the scheme its report finds', async ($, on) => {
  const { clock, store, cli } = session(on, { took: [500], reports: [{ ok: true, scheme: 'Feature' }] })
  await start($, clock)
  await callTool($, 'mcp__MobileBuildMCP__build_sim')
  expect(store.get(historyKey(scopeKey('/work/App', 'build_sim · Feature')))).toEqual([500])
  const report = cli.filter(call => call.args[0] === 'report').map(call => call.args.slice(call.args.indexOf('--tool'), call.args.indexOf('--tool') + 4))
  expect(report).toEqual([['--tool', 'build_sim', '--since', String(NOW)]])
})

/** Without a log, nothing says what the run built: it's timed and shown, and kept nowhere. */
test('a run whose log never appears keeps no history, though a scheme was worked out', async ($, on) => {
  const { clock, store, toasts } = session(on, { scheme: 'App', took: [30_000] })
  await start($, clock)
  await callTool($, 'mcp__MobileBuildMCP__build_sim')
  expect(toasts.at(-1)).toBe('✓ build_sim · 0:30')
  expect([...store.keys()].filter(key => /^(durations|failed|updated|tests)\./.test(key))).toEqual([])
})

/**
 * Until a run's log names its scheme, the scheme worked out for it picks what it's measured against. Here, the test total
 * its progress is counted out of: `kept` gives a scope `tests` tests, written lately, and `countedOutOf` reads, for each
 * run in turn, the total its first progress read was counted out of.
 */
const kept = (scope: string, tests: number) => {
  const key = scopeKey('/work/App', scope)
  return { [historyKey(key)]: [10_000], [updatedKey(key)]: NOW, [testsKey(key)]: tests }
}
function countedOutOf(cli: { args: readonly string[] }[]): (string | undefined)[] {
  const firsts = new Map<string, readonly string[]>()
  for (const call of cli.filter(call => call.args[0] === 'phase')) {
    const since = call.args[call.args.indexOf('--since') + 1] ?? ''
    if (!firsts.has(since)) firsts.set(since, call.args)
  }
  return [...firsts.values()].map(args => (args.includes('--expected') ? args[args.indexOf('--expected') + 1] : undefined))
}

/** A MobileBuildMCP call that names no scheme builds the profile's: that's what it's measured against. */
test("a run whose call names no scheme is measured against the profile's scheme", async ($, on) => {
  const { clock, cli } = session(on, { scheme: 'App', stored: kept('test_sim · App', 7), took: [30_000] })
  await start($, clock)
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  expect(countedOutOf(cli)).toEqual(['7'])
})

const switched = (profile: string) => JSON.stringify({ schema: 'mobilebuildmcp.output.session-profile', data: { previousProfile: 'unit', currentProfile: profile } })

/** A profile chosen before any answer listed the profiles builds its own scheme, which the config names. */
test("a run after choosing a profile is measured against that profile's scheme", async ($, on) => {
  const { clock, cli } = session(on, { scheme: 'AppTests', profiles: { app: 'App', unit: 'AppTests' }, stored: { ...kept('test_sim · App', 7), ...kept('test_sim · AppTests', 3) }, took: [30_000], outputs: { session_use_defaults_profile: switched('app') } })
  await start($, clock)
  await callTool($, 'mcp__MobileBuildMCP__session_use_defaults_profile', { profile: 'app' })
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  expect(countedOutOf(cli)).toEqual(['7'])
  expect(cli.some(call => call.args.join(' ') === 'project --profiles --profile app')).toBe(true)
})

/** Under Xcode, MobileBuildMCP writes Xcode's selection at its start over the profile active then, and no other. */
test("under Xcode, the scheme selected at the server's start is the active profile's", async ($, on) => {
  const { clock, cli } = session(on, {
    scheme: 'AppTests', profiles: { app: 'App', unit: 'AppTests' }, xcode: { activeProfile: 'unit', scheme: 'Feature', follows: false },
    stored: { ...kept('test_sim · Feature', 7), ...kept('test_sim · App', 3) }, took: [30_000, 40_000], outputs: { session_use_defaults_profile: switched('app') },
  })
  await start($, clock)
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  await callTool($, 'mcp__MobileBuildMCP__session_use_defaults_profile', { profile: 'app' })
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  expect(countedOutOf(cli)).toEqual(['7', '3'])
})

/** The run's log says what it builds, so Xcode's selection isn't read before each run, though MobileBuildMCP follows it. */
test('no selection in Xcode is read before a run', async ($, on) => {
  const { clock, cli } = session(on, { scheme: 'AppTests', xcode: { activeProfile: 'unit', scheme: 'Feature', follows: true }, selections: ['Core'], took: [30_000, 40_000] })
  await start($, clock)
  await callTool($, 'mcp__MobileBuildMCP__build_sim')
  await callTool($, 'mcp__MobileBuildMCP__build_sim')
  expect(cli.some(call => call.args.includes('--xcuserstate'))).toBe(false)
})

/** The server's own listing of its defaults is newer than the selection at its start. */
test("a listing of the session's defaults wins over the selection at the server's start", async ($, on) => {
  const listed = JSON.stringify({ schema: 'mobilebuildmcp.output.session-defaults', data: { currentProfile: 'unit', profiles: { unit: { scheme: 'AppTests' } } } })
  const { clock, cli } = session(on, { scheme: 'AppTests', xcode: { activeProfile: 'unit', scheme: 'Feature', follows: true }, stored: { ...kept('test_sim · AppTests', 3), ...kept('test_sim · Feature', 7) }, took: [30_000], outputs: { session_show_defaults: listed } })
  await start($, clock)
  await callTool($, 'mcp__MobileBuildMCP__session_show_defaults')
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  expect(countedOutOf(cli)).toEqual(['3'])
})

/** A listed profile whose scheme is JSON's null names none, so the config's is asked for. */
test("a listed profile's null scheme falls back to the config's", async ($, on) => {
  const listed = JSON.stringify({ schema: 'mobilebuildmcp.output.session-defaults', data: { currentProfile: 'unit', profiles: { unit: { scheme: null } } } })
  const { clock, cli } = session(on, { scheme: 'AppTests', profiles: { unit: 'AppTests' }, stored: kept('test_sim · AppTests', 3), took: [30_000], outputs: { session_show_defaults: listed } })
  await start($, clock)
  await callTool($, 'mcp__MobileBuildMCP__session_show_defaults')
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  expect(countedOutOf(cli)).toEqual(['3'])
})

/** MobileBuildMCP names its global defaults `(default)`: the config's `sessionDefaults`, which the CLI answers for. */
test("after switching to the global defaults, a run is measured against their scheme", async ($, on) => {
  const { clock, cli } = session(on, { scheme: 'AppTests', profiles: { '(default)': 'Global' }, stored: kept('test_sim · Global', 5), took: [30_000], outputs: { session_use_defaults_profile: switched('(default)') } })
  await start($, clock)
  await callTool($, 'mcp__MobileBuildMCP__session_use_defaults_profile', { global: true })
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  expect(countedOutOf(cli)).toEqual(['5'])
  expect(cli.some(call => call.args.join(' ') === 'project --profiles --profile (default)')).toBe(true)
})

/** A server not started yet when the session begins is looked for again, not taken as one Xcode didn't start. */
test("Xcode's selection is read once MobileBuildMCP's server is found", async ($, on) => {
  const { clock, cli } = session(on, { scheme: 'AppTests', xcode: { activeProfile: 'unit', scheme: 'Feature', follows: false }, xcodeServerAfter: 1, stored: kept('test_sim · Feature', 7), took: [30_000] })
  await start($, clock)
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  expect(countedOutOf(cli)).toEqual(['7'])
})

/** The start selection is the config's active profile's, even when its answer comes after a switch. */
test("a selection at the server's start answered after a profile switch stays the config's active profile's", async ($, on) => {
  let release = () => {}
  const xcodeHeld = new Promise<void>(resolve => (release = resolve))
  const { clock, cli } = session(on, {
    scheme: 'AppTests', profiles: { app: 'App', unit: 'AppTests' }, xcode: { activeProfile: 'unit', scheme: 'Feature', follows: false }, xcodeHeld,
    stored: { ...kept('test_sim · App', 3), ...kept('test_sim · Feature', 7) }, took: [30_000], outputs: { session_use_defaults_profile: switched('app') },
  })
  await start($, clock)
  await callTool($, 'mcp__MobileBuildMCP__session_use_defaults_profile', { profile: 'app' })
  release()
  await clock.settle()
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  expect(countedOutOf(cli)).toEqual(['3'])
})

/** A listing that lands while the start selection is being read is the newer of the two. */
test("a listing before the start selection's answer wins over it", async ($, on) => {
  let release = () => {}
  const xcodeHeld = new Promise<void>(resolve => (release = resolve))
  const listed = JSON.stringify({ schema: 'mobilebuildmcp.output.session-defaults', data: { currentProfile: 'unit', profiles: { unit: { scheme: 'AppTests' } } } })
  const { clock, cli } = session(on, { scheme: 'AppTests', xcode: { activeProfile: 'unit', scheme: 'Feature', follows: false }, xcodeHeld, stored: { ...kept('test_sim · AppTests', 3), ...kept('test_sim · Feature', 7) }, took: [30_000], outputs: { session_show_defaults: listed } })
  await start($, clock)
  await callTool($, 'mcp__MobileBuildMCP__session_show_defaults')
  release()
  await clock.settle()
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  expect(countedOutOf(cli)).toEqual(['3'])
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

/** A checkout removed since, as a worktree deleted days ago, leaves nothing behind: its times and its ledgers go at the next start. */
test("a session's start drops the history and ledgers of a checkout that's gone", async ($, on) => {
  const here = scopeKey('/work/App', 'build_sim · App'), gone = scopeKey('/work/App-old', 'test_sim · App')
  const ledger = { entries: [], updated: NOW - DAY }
  const stored = {
    [historyKey(here)]: [30_000], [updatedKey(here)]: NOW - DAY,
    [historyKey(gone)]: [90_000], [updatedKey(gone)]: NOW - DAY, [testsKey(gone)]: 959,
    'ledger./work/App @ main': ledger, 'ledger./work/App-old @ feat/old': ledger,
  }
  const { clock, store } = session(on, { stored, gone: folders => ({ gone: folders.filter(folder => folder === '/work/App-old') }) })
  await start($, clock)
  expect([...store.keys()].filter(key => !key.startsWith('card.')).sort()).toEqual([historyKey(here), updatedKey(here), 'ledger./work/App @ main'].sort())
})

/** A ledger's checkout is read up to the last ` @ `, as a branch's name has no space: a folder may. */
test("a gone checkout whose path holds ' @ ' has its ledger dropped", async ($, on) => {
  const stored = { 'ledger./work/App @ main': { entries: [], updated: NOW - DAY }, 'ledger./work/a @ b @ feat/x': { entries: [], updated: NOW - DAY } }
  const { clock, store } = session(on, { stored, gone: folders => ({ gone: folders.filter(folder => folder === '/work/a @ b') }) })
  await start($, clock)
  expect([...store.keys()].filter(key => key.startsWith('ledger.'))).toEqual(['ledger./work/App @ main'])
})

/** When the CLI can't say which checkouts are gone, each keeps what it stored: a folder not found is the only reason to drop it. */
test("a checkout that can't be looked at keeps its history", async ($, on) => {
  const here = scopeKey('/work/App', 'build_sim · App')
  const stored = { [historyKey(here)]: [30_000], [updatedKey(here)]: NOW - DAY, 'ledger./work/App @ main': { entries: [], updated: NOW - DAY } }
  const { clock, store } = session(on, { stored, gone: () => new Error('timed out') })
  await start($, clock)
  expect([...store.keys()].filter(key => !key.startsWith('card.')).sort()).toEqual([historyKey(here), updatedKey(here), 'ledger./work/App @ main'].sort())
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
