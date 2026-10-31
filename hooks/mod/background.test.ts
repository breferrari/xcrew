import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'
import type { Report } from './cli'
import { callTool, mapStore, stubCli } from './testing'

const BUILD = 'mcp__MobileBuildMCP__build_sim'
const TEST = 'mcp__MobileBuildMCP__test_sim'
const TASK = 'k4q5tm9v2'
const LOG = '/workspaces/App/logs/test_sim.log'

/** What a call Claude Code moved to the background answers with (Claude Code 2.1.314, docs/findings.md). */
const HANDLE = `MCP tool "plugin:xcrew:MobileBuildMCP/test_sim" is still running after 120s. It was moved to the background as task ${TASK} and keeps running; you'll receive a notification with the result when it completes.`
/** How the CLI reads that handle: no outcome, and the task it names. */
const UNREAD: Partial<Report> = { ok: true, isUnread: true, backgroundTask: TASK, notes: ['xcrew: a note for Claude'] }

/** The task's notification as Claude Code 2.1.314 words one, around `result`. */
function notificationText(result: string, task = TASK) {
  return `<task-notification>\n<task-id>${task}</task-id>\n<status>completed</status>\n<summary>MCP task ${task} (plugin:xcrew:MobileBuildMCP/test_sim) completed.</summary>\n<result>\n${result}\n</result>\n</task-notification>`
}

/**
 * A session in VS Code, where an outcome comes as a toast, whose build or test answers after 2:55 with the handle. The
 * CLI answers `reports` in turn after the handle's; the run's log is `LOG`.
 */
function session(on: On, { surface = 'vscode' as 'vscode' | 'terminal', hold, reports = [] as Partial<Report>[] }: { surface?: 'vscode' | 'terminal'; hold?: Promise<void>; reports?: Partial<Report>[] } = {}) {
  const toasts: string[] = []
  const clock = mock.clock(on)
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
  const cli = stubCli(on, { reports: [UNREAD, ...reports], phase: () => ({ log: LOG, phase: 'testing' }), project: { isGenerated: false, root: '/work/App', branch: 'main', scheme: 'App' } })
  on('tool.call', async (_, e) => {
    // A test run the session holds stays live on the band until `hold` settles.
    if (hold && e.tool.endsWith('test_sim')) await hold
    await clock.advance(175_000)
    return { result: {}, text: HANDLE }
  })
  return { toasts, clock, stored, cli, store }
}

/** The task's notification arriving a minute after the handle, as Claude Code submits it: a turn of its own. */
async function notify($: Engine, clock: { advance: (ms: number) => Promise<void>; settle: () => Promise<void> }, text = notificationText('the server\'s result')) {
  await clock.advance(60_000)
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
  expect(toasts).toEqual(['build_sim · no result yet, 2:55'])
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
  expect(reportCalls(cli).at(-1)).toMatchObject({ args: ['report', '--server', 'MobileBuildMCP', '--kind', 'test', '--notification', '--log', LOG], stdin: text })
  expect(entered.text).toBe(notificationText('shorter'))
  expect(entered.context).toContain('xcrew: a note on the run')
  // The run took from the call to the notification: 2:55, then a minute.
  expect(toasts.at(-1)?.startsWith('✗ test_sim · 3:55')).toBe(true)
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
  expect(toasts.at(-1)?.startsWith('✗ test_sim · 3:55')).toBe(true)
  expect(stored().filter(key => /^ledger\./.test(key)).length).toBe(1)
})

/** The log's verdict alone says how the run ended, not how any test did: the ledger takes no test's result from it. */
test("the log's verdict alone shows the outcome and keeps out of the ledger", async ($, on) => {
  const { toasts, clock, stored } = session(on, { reports: [{ ok: true, isVerdictOnly: true, failures: [], notes: [] }] })
  await callTool($, TEST, { tool_use_id: 'toolu_bg' })
  await notify($, clock)
  expect(toasts.at(-1)?.startsWith('✓ test_sim · 3:55')).toBe(true)
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
  expect(durations).toEqual([[175_000, 410_000]])
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
  expect(toasts).toEqual(['build_sim · no result yet, 2:55'])
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
