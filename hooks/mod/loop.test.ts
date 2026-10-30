import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On, ToolCallResult } from 'claude-code'
import { LOOP_RUNS, LOOP_TESTING_MS, LOOP_WINDOW_MS } from './loop'
import { callTool, stubCli } from './testing'

/** A project whose every test run passes and takes `durationMs`, by the server's own count. */
function project(on: On, durationMs: number) {
  const clock = mock.clock(on, { now: Date.UTC(2026, 9, 30, 12, 0) })
  mock.store(on, {})
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.notify', () => ({ value: { isSent: true, channel: 'terminal_bell' } }))
  stubCli(on, { reports: [{ ok: true, durationMs }] })
  on('tool.call', () => ({ result: {}, text: "the server's result" }))
  return clock
}

const MINUTE = 60_000
const full = ($: Engine, args: Record<string, unknown> = {}) => callTool($, 'mcp__MobileBuildMCP__test_sim', args)
const loopNote = (result: ToolCallResult) => (result.context ?? []).find(line => line.includes('full run'))

/** Runs `count` full suites, `every` apart, and gives each run's loop note. */
async function fullRuns($: Engine, clock: { advance: (ms: number) => Promise<void> }, count: number, every: number, run = full) {
  const notes: (string | undefined)[] = []
  for (let index = 0; index < count; index += 1) {
    if (index > 0) await clock.advance(every)
    notes.push(loopNote(await run($)))
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
    "xcrew: that's the 3rd full run of `test_sim` in 21 min, with 3:30 of testing. Before the next one, ask the `affected` tool which test targets this branch's changes can break, and run those with `-only-testing:`. When it says to run the whole suite, run it; and run the whole suite again before the pull request.",
  )
})

test('after the note the count starts again: the loop hears it every third run, not after each', async ($, on) => {
  const clock = project(on, 70_000)
  const notes = await fullRuns($, clock, 6, 5 * MINUTE)
  expect(notes.map(note => note !== undefined)).toEqual([false, false, true, false, false, true])
})

test('a 20 s suite never trips it, however often it runs', async ($, on) => {
  const clock = project(on, 20_000)
  expect((await fullRuns($, clock, 8, 2 * MINUTE)).filter(note => note !== undefined)).toEqual([])
})

test('a run older than the window no longer counts', async ($, on) => {
  const clock = project(on, 70_000)
  expect((await fullRuns($, clock, 3, 20 * MINUTE)).filter(note => note !== undefined)).toEqual([])
})

test('a selection, a repeat or a run that skips tests is not a full run', async ($, on) => {
  const clock = project(on, 70_000)
  const kinds = [{ extraArgs: ['-only-testing:AppTests'] }, { extraArgs: ['-only-testing:AppTests/GreetingTests/testHello', '-test-iterations', '5'] }, { extraArgs: ['-skip-testing:AppTests/SlowTests'] }]
  for (const args of kinds) {
    expect((await fullRuns($, clock, 3, 5 * MINUTE, tool => full(tool, args))).filter(note => note !== undefined)).toEqual([])
  }
})

test('the Xcode MCP\'s full run counts too, and its note names the affected tool alone', async ($, on) => {
  const clock = project(on, 70_000)
  const notes = await fullRuns($, clock, 3, 10 * MINUTE, tool => callTool(tool, 'mcp__xcode__RunAllTests'))
  expect(notes[2]).toContain('ask the `affected` tool which test targets')
  expect(notes[2]).not.toContain('-only-testing:')
})
