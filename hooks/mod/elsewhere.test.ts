import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On, RenderSurface } from 'claude-code'
import type { Problem, Report } from './cli'
import { callTool, stubCli, submitPrompt } from './testing'

const BAND = {
  plugin: 'xcrew',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 100, scroll: { offset: 0, bodyRows: 10 }, view: {} },
} as const

const FEATURE = { worktree: 'feature', root: '/work/trees/feature', tool: 'test_sim', phase: 'testing 120 of 959' }
const SPIKE = { worktree: 'spike', root: '/work/trees/spike', tool: 'build_sim', phase: 'compiling' }
const FIX = { worktree: 'fix', root: '/work/trees/fix', tool: 'build_sim' }
const PROBLEM: Problem = { status: 'fail', id: 'xcode-mcp/claude-approved', message: "Claude Code isn't approved in Xcode" }

/** A session where `xcrew runs` answers the next of `answers` each time it's asked, the last one again after. */
function session(on: On, answers: unknown[], options: { problems?: Problem[]; surfaces?: RenderSurface[]; reports?: Partial<Report>[]; held?: Promise<void> } = {}) {
  const clock = mock.clock(on, { now: Date.UTC(2026, 10, 1, 12, 0) })
  mock.store(on)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => ({ value: { tool: `mcp__xcrew__${e.name}` } }))
  on('session.surfaces', () => ({ value: options.surfaces ?? ['terminal'] }))
  on('ui.invalidate', () => ({ value: undefined }))
  const statuses: (string | undefined)[] = []
  on('ui.status', (_, e) => {
    statuses.push(e.text)
    return { value: undefined }
  })
  on('ui.toast', () => ({ value: undefined }))
  on('ui.render', ($, e) => $.ui.resolve(e).Text({ children: ['engine'] }))
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('tool.call', async () => {
    if (options.held) await options.held
    await clock.advance(3_000)
    return { result: {}, text: 'ok' }
  })
  const queue = [...answers]
  const calls = stubCli(on, { runs: () => (queue.length > 1 ? queue.shift() : queue[0]), problems: options.problems ?? [], reports: options.reports ?? [{ ok: true }] })
  return { clock, calls, statuses }
}

async function bandLines($: Engine): Promise<string[]> {
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  const lines = (await ui.findAll({ type: 'Text' })).map(text => text.text)
  await ui.unmount()
  return lines
}

async function start($: Engine, clock: { settle: () => Promise<void> }) {
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
}

test("another worktree's run shows as a fact on a dim line of its own", async ($, on) => {
  const { clock } = session(on, [[FEATURE]])
  await start($, clock)
  await submitPrompt($, 'go on')
  await clock.settle()
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  const line = await ui.find({ type: 'Text', text: /^elsewhere: / })
  expect(line?.text).toBe('elsewhere: feature · test_sim · testing 120 of 959')
  expect(line?.props.color).toBe('subtle')
  await ui.unmount()
})

test('past two runs, the line counts the rest', async ($, on) => {
  const { clock } = session(on, [[FEATURE, SPIKE, FIX]])
  await start($, clock)
  await submitPrompt($, 'go on')
  await clock.settle()
  expect((await bandLines($)).find(line => line.startsWith('elsewhere: '))).toBe('elsewhere: feature · test_sim · testing 120 of 959; spike · build_sim · compiling; +1 more')
})

test('the line sits below a problem the band ranks first', async ($, on) => {
  const { clock } = session(on, [[FEATURE]], { problems: [PROBLEM] })
  await start($, clock)
  await submitPrompt($, 'go on')
  await clock.settle()
  const lines = await bandLines($)
  expect(lines.findIndex(line => line.startsWith('elsewhere: '))).toBe(lines.length - 1)
  expect(lines.join('')).toContain("Claude Code isn't approved in Xcode")
})

test("the line sits below this session's run while it goes", async ($, on) => {
  let release = () => {}
  const held = new Promise<void>(resolve => (release = resolve))
  const { clock } = session(on, [[FEATURE]], { held })
  await start($, clock)
  const running = callTool($, 'mcp__MobileBuildMCP__build_sim')
  await clock.settle()
  const lines = await bandLines($)
  expect(lines.join('')).toContain('build_sim')
  expect(lines.findIndex(line => line.startsWith('elsewhere: '))).toBe(lines.length - 1)
  release()
  await running
})

/** A prompt and a run starting together start one timer: once the line goes, nothing reads the other worktrees' runs again. */
test('reads started together share one timer, which stops once the line goes', async ($, on) => {
  const { clock, calls } = session(on, [[FEATURE], [FEATURE], []])
  await start($, clock)
  await Promise.all([submitPrompt($, 'one'), callTool($, 'mcp__MobileBuildMCP__build_sim')])
  await clock.settle()
  await clock.advance(5_000)
  await clock.advance(5_000)
  const asked = calls.filter(call => call.args[0] === 'runs').length
  await clock.advance(60_000)
  expect(calls.filter(call => call.args[0] === 'runs').length).toBe(asked)
})

test('the line goes when the CLI answers none, and the refresh stops', async ($, on) => {
  const { clock, calls } = session(on, [[FEATURE], []])
  await start($, clock)
  await submitPrompt($, 'go on')
  await clock.settle()
  await clock.advance(5_000)
  expect((await bandLines($)).some(line => line.startsWith('elsewhere: '))).toBe(false)
  const asked = calls.filter(call => call.args[0] === 'runs').length
  await clock.advance(30_000)
  expect(calls.filter(call => call.args[0] === 'runs').length).toBe(asked)
})

/** A CLI that can't answer leaves the line as it was for as long as a quiet run counts as going, then clears it. */
test("a CLI that can't answer keeps the line 90 seconds, then clears it", async ($, on) => {
  const { clock } = session(on, [[FEATURE], new Error('timed out')])
  await start($, clock)
  await submitPrompt($, 'go on')
  await clock.settle()
  await clock.advance(85_000)
  expect((await bandLines($)).some(line => line.startsWith('elsewhere: '))).toBe(true)
  await clock.advance(10_000)
  expect((await bandLines($)).some(line => line.startsWith('elsewhere: '))).toBe(false)
})

/** Where no band draws, the other worktrees' runs aren't read: the plain status line keeps this session's run only. */
test('where no band draws, the other worktrees are never read', async ($, on) => {
  const { clock, calls, statuses } = session(on, [[FEATURE]], { surfaces: [] })
  await start($, clock)
  await submitPrompt($, 'go on')
  await callTool($, 'mcp__MobileBuildMCP__build_sim')
  expect(calls.some(call => call.args[0] === 'runs')).toBe(false)
  expect(statuses.some(text => text?.includes('elsewhere'))).toBe(false)
})
