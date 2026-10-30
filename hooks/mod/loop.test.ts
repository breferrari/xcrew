import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On, ToolCallResult } from 'claude-code'
import type { Report } from './cli'
import { LOOP_RUNS, LOOP_TESTING_MS, LOOP_WINDOW_MS } from './loop'
import { callTool, stubCli } from './testing'

/**
 * A project whose every test run takes `durationMs`, by the server's own count, and passes 40 tests, unless `report`
 * says how it ended.
 */
function project(on: On, durationMs: number, report: Partial<Report> = { ok: true, tests: 40 }) {
  const clock = mock.clock(on, { now: Date.UTC(2026, 9, 30, 12, 0) })
  mock.store(on, {})
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.notify', () => ({ value: { isSent: true, channel: 'terminal_bell' } }))
  stubCli(on, { reports: [{ ...report, durationMs }] })
  on('tool.call', () => ({ result: {}, text: "the server's result" }))
  return clock
}

const MINUTE = 60_000
const loopNote = (result: ToolCallResult) => (result.context ?? []).find(line => line.includes('full run'))

/** Runs `count` full suites, `every` apart, and gives each run's loop note. */
async function fullRuns($: Engine, clock: ReturnType<typeof mock.clock>, count: number, every: number, tool = 'mcp__MobileBuildMCP__test_sim', args: Record<string, unknown> = {}) {
  const notes: (string | undefined)[] = []
  for (let index = 0; index < count; index += 1) {
    if (index > 0) await clock.advance(every)
    notes.push(loopNote(await callTool($, tool, args)))
  }
  return notes
}

test('the budget is 3 full runs of one scope within 30 minutes, adding up to 3 minutes of testing', () => {
  expect(LOOP_RUNS).toBe(3)
  expect(LOOP_WINDOW_MS).toBe(30 * MINUTE)
  expect(LOOP_TESTING_MS).toBe(3 * MINUTE)
})

test('the third full run in the window sends Claude to the affected tests, once', async ($, on) => {
  const clock = project(on, 70_000)
  const notes = await fullRuns($, clock, 3, 10 * MINUTE)
  expect(notes.slice(0, 2)).toEqual([undefined, undefined])
  expect(notes[2]).toBe(
    "xcrew: that's 3 full runs of `test_sim` in 20 min, with 3:30 of testing. Before the next one, ask the `affected` tool (search for it) which test targets this branch's changes can break, and run those with `-only-testing:`. When it says to run the whole suite, run it; and run the whole suite again before the pull request.",
  )
})

test('after the note the count starts again: the loop hears it every third run, not after each', async ($, on) => {
  const clock = project(on, 70_000)
  const notes = await fullRuns($, clock, 6, 5 * MINUTE)
  expect(notes.map(note => note !== undefined)).toEqual([false, false, true, false, false, true])
})

test('a 20 s suite never trips it, however often it runs', async ($, on) => {
  const clock = project(on, 20_000)
  expect(await fullRuns($, clock, 12, 2 * MINUTE)).toEqual(Array(12).fill(undefined))
})

test('a run older than the window no longer counts', async ($, on) => {
  const clock = project(on, 70_000)
  expect(await fullRuns($, clock, 3, 20 * MINUTE)).toEqual([undefined, undefined, undefined])
})

test('a selection, a repeat or a run that skips tests is not a full run', async ($, on) => {
  const clock = project(on, 70_000)
  const kinds = [{ extraArgs: ['-only-testing:AppTests'] }, { extraArgs: ['-only-testing:AppTests/GreetingTests/testHello', '-test-iterations', '5', '-test-repetition-relaunch-enabled', 'YES'] }, { extraArgs: ['-skip-testing:AppTests/SlowTests'] }]
  for (const args of kinds) {
    expect(await fullRuns($, clock, 3, 5 * MINUTE, 'mcp__MobileBuildMCP__test_sim', args)).toEqual([undefined, undefined, undefined])
  }
})

test('the whole scheme repeated, or narrowed or retried by another flag, is not a full run either', async ($, on) => {
  const clock = project(on, 70_000)
  const kinds = [['-test-iterations', '5'], ['-only-test-configuration', 'Fast'], ['-skip-test-configuration', 'Slow'], ['-testPlan', 'Smoke'], ['-retry-tests-on-failure'], ['-run-tests-until-failure']]
  for (const extraArgs of kinds) {
    expect(await fullRuns($, clock, 3, 5 * MINUTE, 'mcp__MobileBuildMCP__test_sim', { extraArgs })).toEqual([undefined, undefined, undefined])
  }
})

test('a run that ran no test, its build failing, does not count', async ($, on) => {
  const clock = project(on, 70_000, { ok: false, failures: [{ title: 'Greeting.swift:4', message: 'cannot find greet in scope', isTest: false }] })
  expect(await fullRuns($, clock, 3, 5 * MINUTE)).toEqual([undefined, undefined, undefined])
})

test('the Xcode MCP\'s full run counts too, and its note names the affected tool alone', async ($, on) => {
  const clock = project(on, 70_000)
  const notes = await fullRuns($, clock, 3, 10 * MINUTE, 'mcp__xcode__RunAllTests')
  expect(notes[2]).toContain('ask the `affected` tool (search for it) which test targets')
  expect(notes[2]).not.toContain('-only-testing:')
})
