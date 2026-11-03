import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'
import type { Phase, Report } from './cli'
import { callTool, mapStore, stubCli } from './testing'

const BUILD = 'mcp__MobileBuildMCP__build_sim'
const TEST = 'mcp__MobileBuildMCP__test_sim'
const TASK = 'k4q5tm9v2'
const LOG = '/workspaces/App/logs/test_sim.log'
/**
 * How long a call takes before it answers with the handle, and how long after that its notification comes. Short: the
 * clock is fake, but each second of it runs the mod's one-second ticker, whose phase read is real work.
 */
const CALL_MS = 5_000
const NOTIFIED_AFTER_MS = 1_000

/** What a call Claude Code moved to the background answers with (Claude Code 2.1.314, docs/findings.md). */
const HANDLE = `MCP tool "plugin:xcrew:MobileBuildMCP/test_sim" is still running after 120s. It was moved to the background as task ${TASK} and keeps running; you'll receive a notification with the result when it completes.`
/** How the CLI reads that handle: no outcome, and the task it names. */
const UNREAD: Partial<Report> = { ok: true, isUnread: true, backgroundTask: TASK, notes: ['xcrew: a note for Claude'] }

/** The task's notification as Claude Code 2.1.314 words one, around `result`. */
function notificationText(result: string, task = TASK) {
  return `<task-notification>\n<task-id>${task}</task-id>\n<status>completed</status>\n<summary>MCP task ${task} (plugin:xcrew:MobileBuildMCP/test_sim) completed.</summary>\n<result>\n${result}\n</result>\n</task-notification>`
}

/**
 * A session in VS Code, where an outcome comes as a toast, whose build or test answers after 0:05 with the handle. The
 * CLI answers `reports` in turn after the handle's; the run's log is `LOG`.
 */
function session(
  on: On,
  { surface = 'vscode' as 'vscode' | 'terminal', hold, reports = [] as Partial<Report>[], logSeen = true, phase, callMs = CALL_MS }: { surface?: 'vscode' | 'terminal'; hold?: Promise<void>; reports?: Partial<Report>[]; logSeen?: boolean; phase?: (args: readonly string[]) => Phase; callMs?: number } = {},
) {
  const toasts: string[] = []
  const clock = mock.clock(on, { now: Date.UTC(2026, 10, 2, 10, 0) })
  const store = mapStore(on)
  const stored = () => [...store.keys()]
  on('session.surfaces', () => ({ value: [surface] }))
  on('ui.toast', (_, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.notify', () => ({ value: { isSent: true, channel: 'terminal_bell' } }))
  on('ui.render', ($, e) => $.ui.resolve(e).Text({ children: ['as the engine draws it'] }))
  // The prompt enters as the hooks above left it.
  on('prompt.submit', (_, e) => ({ text: e.text, ...(e.context ? { context: e.context } : {}), origin: e.origin }))
  const cli = stubCli(on, { reports: [UNREAD, ...reports], phase: phase ?? (() => (logSeen ? { log: LOG, phase: 'testing', scheme: 'App' } : {})), project: { isGenerated: false, root: '/work/App', branch: 'main', scheme: 'App' } })
  on('tool.call', async (_, e) => {
    // A test run the session holds stays live on the band until `hold` settles.
    if (hold && e.tool.endsWith('test_sim')) await hold
    await clock.advance(callMs)
    return { result: {}, text: HANDLE }
  })
  return { toasts, clock, stored, cli, store }
}

/** The task's notification arriving a second after the handle, as Claude Code submits it: a turn of its own. */
async function notify($: Engine, clock: { advance: (ms: number) => Promise<void>; settle: () => Promise<void> }, text = notificationText('the server\'s result')) {
  await clock.advance(NOTIFIED_AFTER_MS)
  const entered = await $.prompt.submit({ text, wait: false, origin: { kind: 'task-notification' } })
  await clock.settle()
  return entered
}

/** The row of a background task's notification, as Claude Code 2.1.314 raised it live: `task` carries its id and status only. */
async function notificationRow($: Engine, clock: { advance: (ms: number) => Promise<void>; settle: () => Promise<void> }, task: { id: string; status: string; toolUseId?: string; durationMs?: number }, surface: 'vscode' | 'terminal' = 'vscode') {
  const ui = await $.ui.mount({
    plugin: 'xcrew',
    surface,
    component: 'UserMessage',
    requestId: 'message-1',
    props: { text: 'A background task ended.', origin: { kind: 'task-notification' }, task },
  } as never)
  await ui.unmount()
  // The line is shown just after the drawing, which changes nothing itself.
  await clock.advance(1)
  await clock.settle()
}

const reportCalls = (cli: { args: readonly string[]; stdin?: string }[]) => cli.filter(call => call.args[0] === 'report')

test('a build that answers with no outcome is neither passed nor failed, and nothing is recorded', async ($, on) => {
  const { toasts, stored } = session(on)
  await callTool($, BUILD, { tool_use_id: 'toolu_bg' })
  expect(toasts).toEqual(['build_sim · no result yet, 0:05'])
  expect(stored().filter(key => /^(durations|updated|where|tests|ledger)\./.test(key))).toEqual([])
})

/** The notification carries the server's result: read as the call's, it's what Claude reads, with xcrew's notes. */
test("a backgrounded test run's notification is read as its result", async ($, on) => {
  const failing = { title: 'CrashTests/testOutOfRange', message: 'Crash: Index out of range', isTest: true }
  const { toasts, clock, stored, cli } = session(on, { reports: [{ ok: false, failures: [failing], result: notificationText('shorter'), notes: ['xcrew: a note on the run'] }] })
  await callTool($, TEST, { tool_use_id: 'toolu_bg' })
  const text = notificationText('the server\'s result')
  const entered = await notify($, clock, text)
  // One call: the CLI falls back to the run's log itself when the result can't be read.
  expect(reportCalls(cli).at(-1)).toMatchObject({ args: ['report', '--server', 'MobileBuildMCP', '--kind', 'test', '--passed', '--notification', '--log', LOG], stdin: text })
  expect(entered.text).toBe(notificationText('shorter'))
  expect(entered.context).toContain('xcrew: a note on the run')
  // The run took from the call to the notification: 0:05, then a second.
  expect(toasts.at(-1)?.startsWith('✗ test_sim · 0:06')).toBe(true)
  // It failed: its time is kept apart from the usual one.
  expect(stored().filter(key => /^failed\./.test(key)).length).toBe(1)
  expect(stored().filter(key => /^ledger\./.test(key)).length).toBe(1)
})

/** #227 keyed the row by a `toolUseId` the live row never carries: the task's id names it. */
test('the notification row names the call by its task id', async ($, on) => {
  const { toasts, clock } = session(on)
  await callTool($, BUILD, { tool_use_id: 'toolu_bg' })
  await notify($, clock, notificationText('', TASK).replace('completed', 'killed'))
  await notificationRow($, clock, { id: TASK, status: 'killed' })
  expect(toasts.at(-1)).toBe("build_sim's background task was killed")
})

/** A result that can't be read leaves the run's log: its verdict and its bundle's tests. */
test("a notification whose result can't be read is told from the run's log and its bundle", async ($, on) => {
  const failing = { title: 'CrashTests/testOutOfRange', message: 'Crash: Index out of range', isTest: true }
  const { toasts, clock, stored, cli } = session(on, { reports: [{ ok: false, failures: [failing], bundle: '/bundles/Run.xcresult', notes: [] }] })
  await callTool($, TEST, { tool_use_id: 'toolu_bg' })
  await notify($, clock)
  expect(reportCalls(cli).length).toBe(2)
  expect(toasts.at(-1)?.startsWith('✗ test_sim · 0:06')).toBe(true)
  expect(stored().filter(key => /^ledger\./.test(key)).length).toBe(1)
})

/** The log's verdict alone says how the run ended, not how any test did: the ledger takes no test's result from it. */
test("the log's verdict alone shows the outcome and keeps out of the ledger", async ($, on) => {
  const { toasts, clock, stored } = session(on, { reports: [{ ok: true, isVerdictOnly: true, failures: [], notes: [] }] })
  await callTool($, TEST, { tool_use_id: 'toolu_bg' })
  await notify($, clock)
  expect(toasts.at(-1)?.startsWith('✓ test_sim · 0:06')).toBe(true)
  expect(stored().filter(key => /^durations\./.test(key)).length).toBe(1)
  expect(stored().filter(key => /^ledger\./.test(key))).toEqual([])
})

/** The server says how long the run took: the notification may come long after, once Claude's turn has ended. */
test("a notification's run takes the server's own time", async ($, on) => {
  const { toasts, clock } = session(on, { reports: [{ ok: true, failures: [], notes: [], durationMs: 180_000 }] })
  await callTool($, TEST, { tool_use_id: 'toolu_bg' })
  await notify($, clock)
  expect(toasts.at(-1)?.startsWith('✓ test_sim · 3:00')).toBe(true)
})

/** Runs that ended while the task ran keep their times: the history is read when the notification comes. */
test('a notification keeps the times of runs that ended meanwhile', async ($, on) => {
  const { clock, store } = session(on, { reports: [{ ok: true, failures: [], notes: [] }, { ok: true, failures: [], notes: [] }] })
  await callTool($, TEST, { tool_use_id: 'toolu_bg' })
  await callTool($, TEST, { tool_use_id: 'toolu_fg' })
  await notify($, clock)
  const durations = [...store.entries()].filter(([key]) => key.startsWith('durations.')).map(([, runs]) => runs)
  // The run in the foreground took its 5 s; the backgrounded one, both calls and the second before its notification.
  expect(durations).toEqual([[5_000, 11_000]])
})

/** A log that appeared only after the call moved to the background names the scheme in the notification's report. */
test('a run whose log the call never saw is kept under the scheme its report names', async ($, on) => {
  const { clock, store } = session(on, { logSeen: false, reports: [{ ok: true, failures: [], notes: [], scheme: 'Feature' }] })
  await callTool($, TEST, { tool_use_id: 'toolu_bg' })
  await notify($, clock)
  const durations = [...store.entries()].filter(([key]) => key.startsWith('durations.'))
  expect(durations.map(([key]) => key.endsWith('test_sim · Feature'))).toEqual([true])
})

/** A log the call never saw, as one that appears only after Claude Code moved it, the CLI finds from the tool and its start. */
test("a run whose log the call never saw has its notification's report find it", async ($, on) => {
  const { clock, cli } = session(on, { logSeen: false, reports: [{ ok: true, failures: [], notes: [] }] })
  await callTool($, TEST, { tool_use_id: 'toolu_bg' })
  await notify($, clock)
  const notified = reportCalls(cli).filter(call => call.args.includes('--notification'))
  expect(notified.map(call => call.args.slice(call.args.indexOf('--tool'), call.args.indexOf('--tool') + 2))).toEqual([['--tool', 'test_sim']])
  // The call started when the session's clock did, 10:00 UTC on November 2, 2026.
  expect(notified.map(call => call.args.slice(call.args.indexOf('--since'), call.args.indexOf('--since') + 2))).toEqual([['--since', '1793613600000']])
  expect(notified[0]?.args).not.toContain('--log')
})

/** The Xcode MCP writes no log, so its notification's report isn't asked to look for one. */
test("an Xcode MCP call's notification is read without looking for a log", async ($, on) => {
  const { clock, cli } = session(on, { logSeen: false, reports: [{ ok: true, failures: [], notes: [] }] })
  await callTool($, 'mcp__xcode__BuildProject', { tool_use_id: 'toolu_bg' })
  await notify($, clock)
  const notified = reportCalls(cli).filter(call => call.args.includes('--notification'))
  expect(notified).toHaveLength(1)
  expect(notified[0]?.args).not.toContain('--tool')
})

/** Kept under the scheme its report names, a run counts that scheme's failed runs, not those of the scheme first guessed. */
test("a run kept under its report's scheme adds to that scheme's failed runs", async ($, on) => {
  const { clock, store } = session(on, { logSeen: false, reports: [{ ok: false, failures: [], notes: [], scheme: 'Feature' }] })
  store.set('failed./work/App\u001ftest_sim · App', [111_111])
  await callTool($, TEST, { tool_use_id: 'toolu_bg' })
  await notify($, clock)
  const feature = [...store.entries()].filter(([key]) => key.startsWith('failed.') && key.endsWith('test_sim · Feature')).map(([, runs]) => runs)
  expect(feature).toHaveLength(1)
  expect(feature[0]).not.toContain(111_111)
})

/** A build and run's log is read as one whose build's success doesn't end it: the mod says it launches after its build. */
test("a build and run's log is read as one that launches after its build", async ($, on) => {
  const { clock, cli } = session(on, { surface: 'terminal', reports: [{ ok: true, failures: [], notes: [] }] })
  await callTool($, 'mcp__MobileBuildMCP__build_run_sim', { tool_use_id: 'toolu_run' })
  await clock.advance(2_000)
  await notify($, clock)
  const phases = cli.filter(call => call.args[0] === 'phase')
  expect(phases.length).toBeGreaterThan(0)
  expect(phases.every(call => call.args.includes('--launches'))).toBe(true)
  expect(reportCalls(cli).filter(call => call.args.includes('--notification')).map(call => call.args.includes('--launches'))).toEqual([true])
})

/** Drawn before the notification is read, the row leaves the call to it, and says nothing yet. */
test('a row drawn before its notification is read leaves the call to be read', async ($, on) => {
  const { toasts, clock } = session(on, { reports: [{ ok: false, failures: [], notes: [] }] })
  await callTool($, TEST, { tool_use_id: 'toolu_bg' })
  await notificationRow($, clock, { id: TASK, status: 'completed' })
  await notify($, clock)
  expect(toasts.some(toast => toast.includes('ended in the background'))).toBe(false)
  expect(toasts.at(-1)?.startsWith('✗ test_sim')).toBe(true)
})

/** A failed run read from its notification names the pinned Xcode as a foreground failure does: once a session. */
test('a backgrounded failure names the pin once a session', async ($, on) => {
  const pin = 'xcrew: builds use Xcode 27.2 while the project pins Xcode 26.5 (.xcode-version): a different SDK may be the cause.'
  const failed: Partial<Report> = { ok: false, failures: [], notes: [], pinNote: pin, pin: '26.5 (.xcode-version)' }
  const { clock } = session(on, { reports: [failed, { ...UNREAD, backgroundTask: 'b8second' }, failed] })
  await callTool($, TEST, { tool_use_id: 'toolu_bg' })
  expect((await notify($, clock)).context).toContain(pin)
  await callTool($, TEST, { tool_use_id: 'toolu_bg2' })
  expect((await notify($, clock, notificationText('the server\'s result', 'b8second'))).context ?? []).not.toContain(pin)
})

/** Read, the run has its own outcome: the row's line that it ended in the background isn't said as well. */
test('a notification read for its result has no background line besides', async ($, on) => {
  const { toasts, clock } = session(on, { reports: [{ ok: true, failures: [], notes: [] }] })
  await callTool($, TEST, { tool_use_id: 'toolu_bg' })
  await notify($, clock)
  await notificationRow($, clock, { id: TASK, status: 'completed' })
  expect(toasts.some(toast => toast.includes('ended in the background'))).toBe(false)
})

/** Neither the result nor the log says how it ended: the row's line stands. */
test('a notification nothing can be read from leaves the background line', async ($, on) => {
  const { toasts, clock } = session(on, { reports: [{ ok: true, isUnread: true, notes: [] }] })
  await callTool($, TEST, { tool_use_id: 'toolu_bg' })
  const entered = await notify($, clock)
  await notificationRow($, clock, { id: TASK, status: 'completed' })
  expect(entered.text).toBe(notificationText('the server\'s result'))
  expect(toasts.at(-1)).toBe('test_sim ended in the background: its result is in the conversation')
})

test("a notification naming no call waiting enters as it is, and the CLI isn't asked", async ($, on) => {
  const { toasts, clock, cli } = session(on)
  await callTool($, BUILD, { tool_use_id: 'toolu_bg' })
  const text = notificationText('another task\'s result', 'x9other')
  const entered = await notify($, clock, text)
  await notificationRow($, clock, { id: 'x9other', status: 'completed' })
  expect(entered.text).toBe(text)
  expect(reportCalls(cli).length).toBe(1)
  expect(toasts).toEqual(['build_sim · no result yet, 0:05'])
})

/** A clean answers with plain text and no outcome to read; it's never a call waiting in the background. */
test('a clean is never one with no result yet', async ($, on) => {
  const { toasts } = session(on)
  await callTool($, 'mcp__MobileBuildMCP__clean', { tool_use_id: 'toolu_clean' })
  expect(toasts.some(toast => toast.includes('no result yet'))).toBe(false)
})

test('a call with no result yet still hands Claude the notes the CLI had for it', async ($, on) => {
  session(on)
  const answered = await callTool($, BUILD, { tool_use_id: 'toolu_bg' })
  expect(answered.context).toContain('xcrew: a note for Claude')
})

/** The notification belongs to the earlier call: a run going meanwhile keeps the band. */
test('a notification that arrives while another run is going leaves that run on the band', async ($, on) => {
  let release = () => {}
  const hold = new Promise<void>(resolve => (release = resolve))
  const { clock } = session(on, { surface: 'terminal', hold })
  await callTool($, BUILD, { tool_use_id: 'toolu_bg' })
  const running = callTool($, TEST, { tool_use_id: 'toolu_live' })
  await clock.settle()
  await notificationRow($, clock, { id: TASK, status: 'completed' }, 'terminal')
  const band = await $.ui.mount({ plugin: 'xcrew', component: 'AbovePrompt', surface: 'terminal', props: { hasSurvey: false, isWorking: true, maxRows: 10, bodyColumns: 100, scroll: { offset: 0, bodyRows: 10 }, view: {} } } as never)
  expect(await band.find({ type: 'Text', text: /^test_sim/ })).toBeDefined()
  expect(await band.find({ type: 'Text', text: /ended in the background/ })).toBeUndefined()
  await band.unmount()
  release()
  await running
})

/** A subagent's run moved to the background keeps saying which subagent started it, once its notification is read. */
test("a backgrounded subagent's run keeps its label on the band's outcome", async ($, on) => {
  const { clock } = session(on, { surface: 'terminal', reports: [{ ok: true, detail: '5 passed' }] })
  on('agent.list', () => ({ value: [{ id: 'a1', description: 'Fix login tests', type: 'general-purpose', status: 'running' as const }] }))
  await callTool($, TEST, { agentId: 'a1' })
  await notify($, clock, notificationText("the server's result"))
  const band = await $.ui.mount({ plugin: 'xcrew', component: 'AbovePrompt', surface: 'terminal', props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 120, scroll: { offset: 0, bodyRows: 10 }, view: {} } } as never)
  const text = (await band.findAll({ type: 'Text' })).map(found => found.text).join('')
  await band.unmount()
  expect(text).toContain('5 passed')
  expect(text).toContain(' · by "Fix login tests"')
})

/** A backgrounded run is read at its notification: it asks for its passed tests there while its branch has a red waiting. */
test("a backgrounded test run's notification asks for its passed tests while a red waits", async ($, on) => {
  const { clock, cli, store } = session(on, { reports: [{ ok: true, passed: [{ test: 'CrashTests/testOutOfRange' }] }] })
  store.set('ledger./work/App @ main', { entries: [{ test: 'CrashTests/testOutOfRange', red: { scope: 'test_sim · App', at: 0, message: 'Crash' }, failing: 'test_sim · App', last: 0 }], updated: 0 })
  await callTool($, TEST, { tool_use_id: 'toolu_bg' })
  await notify($, clock)
  expect(reportCalls(cli).at(-1)?.args).toEqual(['report', '--server', 'MobileBuildMCP', '--kind', 'test', '--passed', '--notification', '--log', LOG])
})

/** What the ledger said at the run's start may be old by its notification, as after a branch switch: it asks either way. */
test("a backgrounded test run's notification asks for its passed tests though no red waited at its start", async ($, on) => {
  const { clock, cli, store } = session(on, { reports: [{ ok: true, passed: [{ test: 'CrashTests/testOutOfRange' }] }] })
  await callTool($, TEST, { tool_use_id: 'toolu_bg' })
  store.set('ledger./work/App @ main', { entries: [{ test: 'CrashTests/testOutOfRange', red: { scope: 'test_sim · App', at: 0, message: 'Crash' }, failing: 'test_sim · App', last: 0 }], updated: 0 })
  await notify($, clock)
  expect(reportCalls(cli).at(-1)?.args).toContain('--passed')
})

// MARK: Followed in the background

const BAND = {
  plugin: 'xcrew',
  component: 'AbovePrompt',
  surface: 'terminal',
  props: { hasSurvey: false, isWorking: true, maxRows: 10, bodyColumns: 100, scroll: { offset: 0, bodyRows: 10 }, view: {} },
} as const

/** Whether the band, as drawn now, shows a text matching `text`. */
async function bandShows($: Engine, text: RegExp): Promise<boolean> {
  const band = await $.ui.mount(BAND)
  const found = await band.find({ type: 'Text', text })
  await band.unmount()
  return found !== undefined
}

const phaseCalls = (cli: { args: readonly string[] }[], tool = 'test_sim') => cli.filter(call => call.args[0] === 'phase' && call.args.includes(tool)).length

/** Moved to the background, a run goes on: the band keeps it going, its phase read from its log, until it ends. */
test('a run moved to the background stays on the band, going, with its phase', async ($, on) => {
  const { clock, cli } = session(on, { surface: 'terminal' })
  await callTool($, TEST, { tool_use_id: 'toolu_bg' })
  const read = phaseCalls(cli)
  await clock.advance(5_000)
  expect(phaseCalls(cli)).toBeGreaterThan(read)
  expect(await bandShows($, /^test_sim$/)).toBe(true)
  expect(await bandShows($, /in the background/)).toBe(true)
  expect(await bandShows($, /^testing$/)).toBe(true)
  expect(await bandShows($, /no result yet/)).toBe(false)
  // The notification ends it: its log is read no more.
  await notify($, clock)
  const atNotification = phaseCalls(cli)
  await clock.advance(5_000)
  expect(phaseCalls(cli)).toBe(atNotification)
})

/** The log's verdict ends the band; the notification still records the run, once. */
test("the log's verdict ends the band, and the notification records the run once", async ($, on) => {
  let outcome: boolean | undefined
  const { clock, cli, stored } = session(on, { surface: 'terminal', reports: [{ ok: false, failures: [], notes: [] }], phase: () => ({ log: LOG, phase: 'testing', scheme: 'App', ...(outcome === undefined ? {} : { outcome }) }) })
  await callTool($, TEST, { tool_use_id: 'toolu_bg' })
  outcome = false
  await clock.advance(2_000)
  expect(await bandShows($, /^✗$/)).toBe(true)
  const read = phaseCalls(cli)
  await clock.advance(5_000)
  expect(phaseCalls(cli)).toBe(read)
  await notify($, clock)
  expect(reportCalls(cli).filter(call => call.args.includes('--notification')).length).toBe(1)
  expect(stored().filter(key => /^failed\./.test(key)).length).toBe(1)
})

/** A run in the background stays followed, its log however quiet, until its verdict or its notification ends it. */
test('a run whose log goes quiet stays on the band, followed until its notification', async ($, on) => {
  let quiet = false
  const { clock, cli } = session(on, { surface: 'terminal', phase: () => ({ log: LOG, phase: 'testing', scheme: 'App', ...(quiet ? { quiet: true } : {}) }) })
  await callTool($, TEST, { tool_use_id: 'toolu_bg' })
  quiet = true
  await clock.advance(2_000)
  expect(await bandShows($, /test_sim/)).toBe(true)
  const read = phaseCalls(cli)
  await clock.advance(60_000)
  expect(phaseCalls(cli)).toBeGreaterThan(read)
})

/** Two runs in the background each follow their own log, and each ends on its own. */
test('two runs in the background each follow their own log', async ($, on) => {
  let buildDone = false
  const { clock, cli } = session(on, { surface: 'terminal', phase: args => (args.includes('build_sim') && buildDone ? { log: '/logs/build.log', phase: 'linking', outcome: true } : { log: args.includes('build_sim') ? '/logs/build.log' : LOG, phase: 'working' }) })
  await callTool($, BUILD, { tool_use_id: 'toolu_build' })
  await callTool($, TEST, { tool_use_id: 'toolu_test' })
  const [builds, tests] = [phaseCalls(cli, 'build_sim'), phaseCalls(cli, 'test_sim')]
  await clock.advance(3_000)
  expect(phaseCalls(cli, 'build_sim')).toBeGreaterThan(builds)
  expect(phaseCalls(cli, 'test_sim')).toBeGreaterThan(tests)
  buildDone = true
  await clock.advance(2_000)
  const [builtAt, testedAt] = [phaseCalls(cli, 'build_sim'), phaseCalls(cli, 'test_sim')]
  await clock.advance(3_000)
  expect(phaseCalls(cli, 'build_sim')).toBe(builtAt)
  expect(phaseCalls(cli, 'test_sim')).toBeGreaterThan(testedAt)
})

/** Every call moved to the background is kept and followed until its notification, however many wait. */
test('every backgrounded call is followed until its notification, however many wait', async ($, on) => {
  // Calls that answer at once, each moved to a task of its own: no tick runs until the clock moves below.
  const tasks: Partial<Report>[] = Array.from({ length: 20 }, (_, call) => ({ ...UNREAD, backgroundTask: `task${call + 1}` }))
  const { clock, cli } = session(on, { surface: 'terminal', callMs: 0, reports: tasks })
  for (let call = 0; call < 21; call += 1) await callTool($, TEST, { tool_use_id: `toolu_${call}` })
  await clock.settle()
  const before = phaseCalls(cli)
  await clock.advance(1_000)
  // One second: one read for each of the 21 calls.
  expect(phaseCalls(cli) - before).toBe(21)
})
