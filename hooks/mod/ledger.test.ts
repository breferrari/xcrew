import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Report } from './cli'
import { callTool, mapStore, runCommand, stubCli } from './testing'

const TEST = 'GreetingTests/testHello'
const FAILED: Partial<Report> = { ok: false, failures: [{ title: TEST, message: 'XCTAssertEqual failed: ("Hi") is not equal to ("Hello")', where: 'GreetingTests.swift:9', isTest: true }] }
const BUILD_FAILED: Partial<Report> = { ok: false, failures: [{ title: 'Greeting.swift:4', message: 'cannot find greet in scope', isTest: false }] }
const PASSED: Partial<Report> = { ok: true, detail: '12 passed' }
const DAY_MS = 24 * 60 * 60_000

/**
 * A project on `branch` (the CLI names it and the project's root), whose test runs report the next of `reports`. The
 * store starts with `stored`; registered tools are collected in `registered`.
 */
function project(on: On, reports: Partial<Report>[], options: { branch?: () => string | Error; stored?: Record<string, unknown>; readsStore?: boolean; reportFails?: () => boolean } = {}) {
  const clock = mock.clock(on, { now: Date.UTC(2026, 9, 30, 12, 0) })
  // A test that reads what the mod kept gets the store as a plain map.
  const store = options.readsStore ? mapStore(on) : (mock.store(on, options.stored ?? {}), undefined)
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
    ...(options.reportFails ? { reportFails: options.reportFails } : {}),
    project: args => {
      if (!args.includes('--branch')) return { isGenerated: false }
      const branch = options.branch?.() ?? 'feat/ledger'
      // A CLI that can't answer: the stand-in fails as a process that timed out would.
      if (branch instanceof Error) throw branch
      return { isGenerated: false, root: '/work/App', branch }
    },
  })
  on('tool.call', () => ({ result: {}, text: 'the server\'s result' }))
  return { clock, registered, store }
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

for (const selection of ['AppTests/GreetingTests', 'AppTests']) {
  test(`a test red under its method is green once a run of ${selection} passes`, async ($, on) => {
    project(on, [FAILED, PASSED])
    await run($, 'AppTests/GreetingTests/testHello')
    await run($, selection)
    expect(await ledgerText($)).toContain(`Red, then green, on feat/ledger (1 test):\n- ${TEST}: red`)
  })
}

test('a pass of a sibling class or another target never ran the test: it stays red', async ($, on) => {
  project(on, [FAILED, PASSED, PASSED])
  await run($, 'AppTests/GreetingTests/testHello')
  await run($, 'AppTests/FarewellTests')
  await run($, 'OtherTests/GreetingTests')
  expect(await ledgerText($)).toContain(`Still red (1):\n- ${TEST}: red`)
})

test('a test red under its target is green once a run of its class in that target passes', async ($, on) => {
  project(on, [FAILED, PASSED])
  await run($, 'AppTests')
  await run($, 'AppTests/GreetingTests')
  expect(await ledgerText($)).toContain(`Red, then green, on feat/ledger (1 test):\n- ${TEST}: red`)
})

test('a run of the target a test may not be in leaves it red, when its failing run selected two targets', async ($, on) => {
  project(on, [FAILED, PASSED])
  await callTool($, 'mcp__MobileBuildMCP__test_sim', { extraArgs: ['-only-testing:AppTests', '-only-testing:OtherTests'] })
  await run($, 'OtherTests')
  expect(await ledgerText($)).toContain(`Still red (1):\n- ${TEST}: red`)
})

test('a Swift Testing selection, its method spelled with (), reaches the test either way', async ($, on) => {
  project(on, [FAILED, PASSED, FAILED, PASSED])
  await run($, 'AppTests/GreetingTests/testHello()')
  await run($, 'AppTests/GreetingTests')
  expect(await ledgerText($)).toContain(`Red, then green, on feat/ledger (1 test):\n- ${TEST}: red`)
})

test('a test red in a whole-suite run is green once a run of its method passes', async ($, on) => {
  project(on, [FAILED, PASSED])
  await run($)
  await run($, 'AppTests/GreetingTests/testHello')
  expect(await ledgerText($)).toContain(`Red, then green, on feat/ledger (1 test):\n- ${TEST}: red`)
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

test('a red test keeps the result bundle of the run it first failed in, for the evidence pack', async ($, on) => {
  const { clock, store } = project(on, [{ ...FAILED, bundle: '/runs/first.xcresult' }, { ...FAILED, bundle: '/runs/second.xcresult' }], { readsStore: true })
  await run($)
  await clock.advance(60 * 60_000)
  await run($)
  const ledger = [...(store?.entries() ?? [])].find(([key]) => key.startsWith('ledger.'))?.[1] as { entries: { test: string; red: { bundle?: string } }[] } | undefined
  expect(ledger?.entries.find(entry => entry.test === TEST)?.red.bundle).toBe('/runs/first.xcresult')
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
  expect(registered).toContainEqual({ name: 'ledger', isDeferred: undefined })
  await run($)
  const shown = await runCommand($, 'xcrew', 'ledger')
  expect(shown.text).toBe(await ledgerText($))
  expect(shown.text).toContain(TEST)
})

test('when the CLI can\'t name the branch, the run goes on and the ledger says it can\'t be read', async ($, on) => {
  project(on, [FAILED], { branch: () => new Error('timed out') })
  const ran = await run($)
  expect(ran.deny).toBeUndefined()
  expect(ran.text).toBe('the server\'s result')
  expect(await ledgerText($)).toBe("The ledger couldn't be read: xcrew's CLI didn't say which branch is checked out. Run `/xcrew doctor`.")
})


test('two days later the times say which day, whatever the time zone', async ($, on) => {
  const { clock } = project(on, [FAILED, PASSED])
  await run($)
  await clock.advance(2 * DAY_MS)
  await run($)
  const [, redDay, greenDay] = /red (\w{3} \d+) \d\d:\d\d .*; green (\w{3} \d+) \d\d:\d\d/.exec(await ledgerText($)) ?? []
  expect(redDay).toBeDefined()
  expect(greenDay).not.toBe(redDay)
})

test('a run whose report the CLI couldn\'t read is no evidence: it turns nothing green', async ($, on) => {
  let fails = false
  project(on, [FAILED, PASSED], { reportFails: () => fails })
  await run($)
  fails = true
  await run($)
  expect(await ledgerText($)).toContain(`Still red (1):\n- ${TEST}`)
})

test('a pass that skipped tests turns nothing green', async ($, on) => {
  project(on, [FAILED, PASSED])
  await run($)
  await callTool($, 'mcp__MobileBuildMCP__test_sim', { extraArgs: ['-skip-testing:AppTests/GreetingTests'] })
  expect(await ledgerText($)).toContain('Still red (1)')
})

test('of the Xcode MCP\'s test tools, only its run of all tests turns a red green', async ($, on) => {
  project(on, [FAILED, PASSED, FAILED, PASSED])
  await callTool($, 'mcp__xcode__RunSomeTests')
  await callTool($, 'mcp__xcode__RunSomeTests')
  expect(await ledgerText($)).toContain('Still red (1)')
  await callTool($, 'mcp__xcode__RunAllTests')
  await callTool($, 'mcp__xcode__RunAllTests')
  expect(await ledgerText($)).toContain('Red, then green')
})

test('a test that fails again elsewhere is green only once that scope passes it', async ($, on) => {
  project(on, [FAILED, PASSED, FAILED, PASSED])
  await run($, 'AppTests')
  await run($, 'AppTests')
  await callTool($, 'mcp__MobileBuildMCP__test_sim', { scheme: 'Other' })
  // The first scope passes again; the test still fails in the other one.
  await run($, 'AppTests')
  expect(await ledgerText($)).toContain(`Still red (1):\n- ${TEST}: red`)
})

test('a failing run turns green the reds it ran without failing them', async ($, on) => {
  const OTHER = 'GreetingTests/testBye'
  const both: Partial<Report> = { ok: false, failures: [FAILED.failures?.[0] ?? { title: '', message: '' }, { title: OTHER, message: 'nope', isTest: true }] }
  project(on, [both, { ok: false, failures: [{ title: OTHER, message: 'still nope', isTest: true }] }])
  await run($)
  await run($)
  const text = await ledgerText($)
  expect(text).toContain(`Red, then green, on feat/ledger (1 test):\n- ${TEST}`)
  expect(text).toContain(`Still red (1):\n- ${OTHER}`)
})

test('two runs ending together each keep their entries', async ($, on) => {
  project(on, [FAILED, { ok: false, failures: [{ title: 'Other/testOther', message: 'nope', isTest: true }] }])
  await Promise.all([run($, 'AppTests'), run($, 'OtherTests')])
  const text = await ledgerText($)
  expect(text).toContain(TEST)
  expect(text).toContain('Other/testOther')
})

test('a test no run has written for two weeks leaves the ledger, while the branch keeps it', async ($, on) => {
  const { clock } = project(on, [FAILED, { ok: false, failures: [{ title: 'Other/testOther', message: 'nope', isTest: true }] }])
  await run($, 'AppTests')
  await clock.advance(15 * DAY_MS)
  await run($, 'OtherTests')
  const text = await ledgerText($)
  expect(text).not.toContain(TEST)
  expect(text).toContain('Other/testOther')
})

// MARK: Flaky or real

const REPEATED = ['-only-testing:AppTests/GreetingTests/testHello', '-test-iterations', '5', '-test-repetition-relaunch-enabled', 'YES']
const repeat = (tool: Engine) => callTool(tool, 'mcp__MobileBuildMCP__test_sim', { extraArgs: REPEATED })
const MIXED: Partial<Report> = { ...FAILED, repeated: [{ test: TEST, failed: 2, passed: 3, runs: 5, verdict: 'flaky' }] }
const CLEAN: Partial<Report> = { ok: true, repeated: [{ test: TEST, failed: 0, passed: 5, runs: 5, verdict: 'passed' }] }
const REAL: Partial<Report> = { ...FAILED, repeated: [{ test: TEST, failed: 5, passed: 0, runs: 5, verdict: 'real' }] }
const SKIPPED: Partial<Report> = { ok: true, repeated: [{ test: TEST, failed: 0, passed: 0, runs: 5, verdict: 'none' }] }

test('a flaky test stays red, marked flaky, and a later pass of one run doesn\'t green it', async ($, on) => {
  project(on, [FAILED, MIXED, PASSED])
  await run($, 'AppTests/GreetingTests/testHello')
  await repeat($)
  await run($, 'AppTests/GreetingTests/testHello')
  const text = await ledgerText($)
  expect(text).toContain(`Still red (1):\n- ${TEST} (flaky: failed 2 of 5 runs)`)
  expect(text).not.toContain('Red, then green')
})

test('a flaky test is green once a repeated run passes it every time', async ($, on) => {
  project(on, [FAILED, MIXED, CLEAN])
  await run($, 'AppTests/GreetingTests/testHello')
  await repeat($)
  await repeat($)
  expect(await ledgerText($)).toContain(`Red, then green, on feat/ledger (1 test):\n- ${TEST} (flaky: failed 2 of 5 runs)`)
})

test('a flaky test that later fails every run is a real failure, no longer marked flaky', async ($, on) => {
  project(on, [FAILED, MIXED, REAL])
  await run($, 'AppTests/GreetingTests/testHello')
  await repeat($)
  await repeat($)
  const text = await ledgerText($)
  expect(text).toContain(`Still red (1):\n- ${TEST}: red`)
  expect(text).not.toContain('flaky')
})

test('a mixed result is flaky even when the failures leave the test out', async ($, on) => {
  project(on, [FAILED, { ok: true, repeated: [{ test: TEST, failed: 2, passed: 3, runs: 5, verdict: 'flaky' }] }])
  await run($, 'AppTests/GreetingTests/testHello')
  await repeat($)
  expect(await ledgerText($)).toContain(`Still red (1):\n- ${TEST} (flaky: failed 2 of 5 runs)`)
})

test('a test that failed every repeated run, with no failure of its own listed, reads as the verdict says', async ($, on) => {
  project(on, [{ ok: false, repeated: [{ test: TEST, failed: 5, passed: 0, runs: 5, verdict: 'real' }] }])
  await repeat($)
  const text = await ledgerText($)
  expect(text).toContain(`Still red (1):\n- ${TEST}: red`)
  expect(text).toMatch(/: failed every run, a real failure$/m)
  expect(text).not.toContain('failed some of its repeated runs')
})

test('a flaky test\'s counts are said once, in its label, as each run updates them', async ($, on) => {
  project(on, [{ ok: false, repeated: [{ test: TEST, failed: 2, passed: 3, runs: 5, verdict: 'flaky' }] }, { ok: false, repeated: [{ test: TEST, failed: 3, passed: 2, runs: 5, verdict: 'flaky' }] }])
  await repeat($)
  await repeat($)
  const text = await ledgerText($)
  expect(text).toContain(`- ${TEST} (flaky: failed 3 of 5 runs): red`)
  expect(text).not.toContain('2 of 5')
})

test('runs that gave no verdict clear nothing', async ($, on) => {
  project(on, [FAILED, MIXED, SKIPPED])
  await run($, 'AppTests/GreetingTests/testHello')
  await repeat($)
  await repeat($)
  expect(await ledgerText($)).toContain(`Still red (1):\n- ${TEST} (flaky`)
})
