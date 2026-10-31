import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Report } from './cli'
import { callTool, mapStore, runCommand, stubCli } from './testing'

const TEST = 'GreetingTests/testHello'
const FAILED: Partial<Report> = { ok: false, failures: [{ title: TEST, message: 'XCTAssertEqual failed: ("Hi") is not equal to ("Hello")', where: 'GreetingTests.swift:9', isTest: true }] }
const BUILD_FAILED: Partial<Report> = { ok: false, failures: [{ title: 'Greeting.swift:4', message: 'cannot find greet in scope', isTest: false }] }
/** A pass whose results list the test as passed, as `xcrew report --passed` reads them. */
const PASSED: Partial<Report> = { ok: true, detail: '12 passed', passed: [{ test: TEST }] }
/** A pass whose results don't hold the test. */
const PASSED_OTHERS: Partial<Report> = { ok: true, detail: '11 passed', passed: [{ test: 'GreetingTests/testBye' }] }
const DAY_MS = 24 * 60 * 60_000

/**
 * A project on `branch` (the CLI names it and the project's root), whose test runs report the next of `reports`. The
 * store starts with `stored`; registered tools are collected in `registered`.
 */
function project(on: On, reports: Partial<Report>[], options: { branch?: () => string | Error; stored?: Record<string, unknown>; readsStore?: boolean; reportFails?: () => boolean; holdFirst?: Promise<void> } = {}) {
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
  const calls = stubCli(on, {
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
  // The first call, with `holdFirst`, stays open until it settles, so another run can end meanwhile.
  let held = options.holdFirst
  on('tool.call', async () => {
    const hold = held
    held = undefined
    await hold
    return { result: {}, text: 'the server\'s result' }
  })
  return { calls, clock, registered, store }
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

test('a test run asks the CLI for its passed tests only while its branch has a red waiting', async ($, on) => {
  const { calls } = project(on, [FAILED, PASSED, PASSED])
  const asked = () => calls.filter(call => call.args[0] === 'report').map(call => call.args.includes('--passed'))
  // Not on a clean ledger, then while the red waits, and not once it's green.
  await run($)
  await ledgerText($)
  await run($)
  await ledgerText($)
  await run($)
  expect(asked()).toEqual([false, true, false])
})

test('a run that a red was written during asks for its passed tests, and turns that red green', async ($, on) => {
  let release = () => {}
  const holdFirst = new Promise<void>(resolve => { release = resolve })
  // The held run's report comes second: the other run ends first, failing the test.
  const { calls } = project(on, [FAILED, PASSED], { holdFirst })
  const held = run($, 'AppTests')
  await run($, 'AppTests/GreetingTests')
  await ledgerText($)
  release()
  await held
  const reports = calls.filter(call => call.args[0] === 'report')
  expect(reports.at(-1)?.args).toContain('--passed')
  expect(await ledgerText($)).toContain(`Red, then green, on feat/ledger (1 test):\n- ${TEST}: red`)
})

test('a red turns green from another tool of the same scheme whose results list it as passed', async ($, on) => {
  project(on, [FAILED, PASSED])
  await callTool($, 'mcp__xcode__RunAllTests')
  await callTool($, 'mcp__xcode__RunSomeTests')
  expect(await ledgerText($)).toContain(`Red, then green, on feat/ledger (1 test):\n- ${TEST}: red`)
})

test('a green an older xcrew inferred from a run\'s selection is read as still red', async ($, on) => {
  const at = Date.UTC(2026, 9, 30, 11, 0)
  const entry = { test: TEST, red: { scope: 'test_sim', at, message: 'gone' }, failing: 'test_sim', green: { scope: 'test_sim › AppTests', at }, last: at }
  project(on, [PASSED], { stored: { 'ledger./work/App @ feat/ledger': { entries: [entry], updated: at } } })
  expect(await ledgerText($)).toContain(`Still red (1):\n- ${TEST}: red`)
})

test('a pass in a scheme that shares the red scheme\'s first part leaves the red red', async ($, on) => {
  project(on, [FAILED, PASSED])
  await callTool($, 'mcp__MobileBuildMCP__test_sim', { scheme: 'Shop · Staging' })
  await callTool($, 'mcp__MobileBuildMCP__test_sim', { scheme: 'Shop · Release' })
  expect(await ledgerText($)).toContain(`Still red (1):\n- ${TEST}: red`)
})

test('a stored ledger with an entry that isn\'t one is read without it', async ($, on) => {
  const at = Date.UTC(2026, 9, 30, 11, 0)
  const entry = { test: TEST, red: { scope: 'test_sim', at, message: 'kept' }, failing: 'test_sim', last: at }
  project(on, [PASSED], { stored: { 'ledger./work/App @ feat/ledger': { entries: [null, entry], updated: at } } })
  expect(await ledgerText($)).toContain(`Still red (1):\n- ${TEST}: red`)
})

test('a red test a passing run doesn\'t list as passed stays red, though the run selected its class', async ($, on) => {
  // The field case: a test deleted since its red, then a run of its class, whose results don't hold it.
  project(on, [FAILED, { ok: true, detail: '4 passed', passed: [{ test: 'GreetingTests/testBye' }, { test: 'GreetingTests/testWave' }] }])
  await run($, 'AppTests/GreetingTests/testHello')
  await run($, 'AppTests/GreetingTests')
  const text = await ledgerText($)
  expect(text).toContain(`Still red (1):\n- ${TEST}: red`)
  expect(text).not.toContain('Red, then green')
})

test('a red test the run lists as passed turns green, whatever the run selected', async ($, on) => {
  project(on, [FAILED, PASSED])
  await run($, 'AppTests/GreetingTests/testHello')
  await run($, 'OtherTests')
  expect(await ledgerText($)).toContain(`Red, then green, on feat/ledger (1 test):\n- ${TEST}: red`)
})

test('a pass that skipped other tests turns green the reds it lists as passed', async ($, on) => {
  project(on, [FAILED, PASSED])
  await run($)
  await callTool($, 'mcp__MobileBuildMCP__test_sim', { extraArgs: ['-skip-testing:AppTests/FarewellTests'] })
  expect(await ledgerText($)).toContain('Red, then green, on feat/ledger (1 test)')
})

test('a pass under another scheme leaves a red red, though it lists the test', async ($, on) => {
  project(on, [FAILED, PASSED])
  await run($)
  await callTool($, 'mcp__MobileBuildMCP__test_sim', { scheme: 'Other' })
  expect(await ledgerText($)).toContain(`Still red (1):\n- ${TEST}: red`)
})

test('a pass with no list of its passed tests turns nothing green', async ($, on) => {
  project(on, [FAILED, { ok: true, detail: '12 passed' }])
  await run($)
  await run($)
  expect(await ledgerText($)).toContain(`Still red (1):\n- ${TEST}: red`)
})

test('a test named with () on one side only is the same test', async ($, on) => {
  project(on, [FAILED, { ok: true, passed: [{ test: `${TEST}()` }] }, { ok: false, failures: [{ title: 'GreetingTests/testWave()', message: 'nope', isTest: true }] }, { ok: true, passed: [{ test: 'GreetingTests/testWave' }] }])
  for (let each = 0; each < 4; each++) await run($)
  expect(await ledgerText($)).toContain('Red, then green, on feat/ledger (2 tests)')
})

const FAILED_IN_TARGET: Partial<Report> = { ok: false, failures: [{ ...FAILED.failures![0]!, target: 'AppTests' }] }

test('a test whose target the report named is green once a pass in that target lists it', async ($, on) => {
  project(on, [FAILED_IN_TARGET, { ok: true, passed: [{ test: TEST, target: 'AppTests' }] }])
  await run($)
  await run($, 'AppTests')
  expect(await ledgerText($)).toContain(`Red, then green, on feat/ledger (1 test):\n- ${TEST}: red`)
})

test('a test of the same name passing in another target leaves a red whose target the report named red', async ($, on) => {
  project(on, [FAILED_IN_TARGET, { ok: true, passed: [{ test: TEST, target: 'OtherTests' }] }])
  await run($)
  await run($)
  expect(await ledgerText($)).toContain(`Still red (1):\n- ${TEST}: red`)
})

test('a test that fails again in another target takes the newest target the report names', async ($, on) => {
  project(on, [FAILED_IN_TARGET, { ok: false, failures: [{ ...FAILED.failures![0]!, target: 'NewTests' }] }, { ok: true, passed: [{ test: TEST, target: 'AppTests' }] }, { ok: true, passed: [{ test: TEST, target: 'NewTests' }] }])
  await run($)
  await run($)
  await run($)
  expect(await ledgerText($)).toContain('Still red (1)')
  await run($)
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

test('an Xcode MCP run of some tests turns a red green when its results list it, and not when they don\'t', async ($, on) => {
  project(on, [FAILED, PASSED_OTHERS, PASSED])
  await callTool($, 'mcp__xcode__RunSomeTests')
  await callTool($, 'mcp__xcode__RunSomeTests')
  expect(await ledgerText($)).toContain('Still red (1)')
  await callTool($, 'mcp__xcode__RunSomeTests')
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
  project(on, [both, { ok: false, failures: [{ title: OTHER, message: 'still nope', isTest: true }], passed: [{ test: TEST }] }])
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
const CLEAN: Partial<Report> = { ok: true, repeated: [{ test: TEST, failed: 0, passed: 5, runs: 5, verdict: 'passed' }], passed: [{ test: TEST }] }
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

// MARK: /xcrew flaky

const OTHER = 'GreetingTests/testWave'
const OTHER_FLAKY: Partial<Report> = {
  ok: false,
  failures: [{ title: OTHER, message: 'XCTAssertTrue failed', where: 'GreetingTests.swift:20', isTest: true }],
  repeated: [{ test: OTHER, failed: 1, passed: 4, runs: 5, verdict: 'flaky' }],
}
const repeatOther = (tool: Engine) =>
  callTool(tool, 'mcp__MobileBuildMCP__test_sim', { extraArgs: ['-only-testing:AppTests/GreetingTests/testWave', '-test-iterations', '5', '-test-repetition-relaunch-enabled', 'YES'] })

test('/xcrew flaky lists the tests marked flaky on this branch, and no other red test', async ($, on) => {
  project(on, [{ ...FAILED, failures: [{ ...FAILED.failures![0]!, title: OTHER }] }, FAILED, MIXED])
  await run($, 'AppTests/GreetingTests/testWave')
  await run($, 'AppTests/GreetingTests/testHello')
  await repeat($)
  expect((await runCommand($, 'xcrew', 'flaky')).text).toBe(`Flaky on feat/ledger (1 test):\n- ${TEST}: failed 2 of 5 runs, in test_sim › AppTests/GreetingTests/testHello`)
})

test('/xcrew flaky names the repeated run that found it flaky, not a later plain run that failed it', async ($, on) => {
  project(on, [MIXED, FAILED])
  await repeat($)
  await run($)
  expect((await runCommand($, 'xcrew', 'flaky')).text).toBe(`Flaky on feat/ledger (1 test):\n- ${TEST}: failed 2 of 5 runs, in test_sim › AppTests/GreetingTests/testHello`)
})

test('/xcrew flaky lists the test found flaky last first, whatever touched the others since', async ($, on) => {
  const { clock } = project(on, [OTHER_FLAKY, MIXED, { ...FAILED, failures: [{ ...FAILED.failures![0]!, title: OTHER }] }])
  await repeatOther($)
  await clock.advance(60_000)
  await repeat($)
  await clock.advance(60_000)
  await run($)
  expect((await runCommand($, 'xcrew', 'flaky')).text).toBe(
    `Flaky on feat/ledger (2 tests):\n- ${TEST}: failed 2 of 5 runs, in test_sim › AppTests/GreetingTests/testHello\n- ${OTHER}: failed 1 of 5 runs, in test_sim › AppTests/GreetingTests/testWave`,
  )
})

test('/xcrew flaky says when a flaky test has since passed every run', async ($, on) => {
  project(on, [FAILED, MIXED, CLEAN])
  await run($, 'AppTests/GreetingTests/testHello')
  await repeat($)
  await repeat($)
  expect((await runCommand($, 'xcrew', 'flaky')).text).toBe(
    `Flaky on feat/ledger (1 test):\n- ${TEST}: failed 2 of 5 runs, in test_sim › AppTests/GreetingTests/testHello; passed every run of a repeated run since, in test_sim › AppTests/GreetingTests/testHello`,
  )
})

test('/xcrew flaky with none marked says so, and without a branch says why', async ($, on) => {
  let branch: string | Error = 'feat/ledger'
  project(on, [FAILED], { branch: () => branch })
  await run($, 'AppTests/GreetingTests/testHello')
  expect((await runCommand($, 'xcrew', 'flaky')).text).toBe('No test is marked flaky on feat/ledger.')
  branch = new Error('timed out')
  expect((await runCommand($, 'xcrew', 'flaky')).text).toBe("The ledger couldn't be read: xcrew's CLI didn't say which branch is checked out. Run `/xcrew doctor`.")
})
