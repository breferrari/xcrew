import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'
import { callTool, stubCli } from './testing'

const BUILD = 'mcp__MobileBuildMCP__build_sim'

/**
 * A session in VS Code, where an outcome comes as a toast, whose build answers after 2:55 with a result the CLI reads as
 * no outcome: what a call Claude moved to the background answers with. Claude Code's mod docs give that answer no shape,
 * so the CLI's verdict stands for it.
 */
function session(on: On, { surface = 'vscode' as 'vscode' | 'terminal', hold }: { surface?: 'vscode' | 'terminal'; hold?: Promise<void> } = {}) {
  const toasts: string[] = []
  const clock = mock.clock(on)
  // The store as a plain map, so the test reads what the mod kept.
  const store = new Map<string, unknown>()
  on('store.get', (_, e) => ({ value: store.get(e.key) }))
  on('store.set', (_, e) => {
    store.set(e.key, e.value)
    return { value: undefined }
  })
  on('store.keys', () => ({ value: [...store.keys()] }))
  on('store.delete', (_, e) => {
    store.delete(e.key)
    return { value: undefined }
  })
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
  stubCli(on, { reports: [{ ok: true, isUnread: true, notes: ['xcrew: a note for Claude'] }] })
  on('tool.call', async (_, e) => {
    // A test run the session holds stays live on the band until `hold` settles.
    if (hold && e.tool.endsWith('test_sim')) await hold
    await clock.advance(175_000)
    return { result: {}, text: 'Task bg-1 is running in the background.' }
  })
  return { toasts, clock, stored }
}

/**
 * The row of a background task's notification, as the engine raises it: `task` names the call that started it by its
 * `tool_use_id`, how the task ended, and how long it ran (Claude Code's types, `UserMessageTask`).
 */
async function notification($: Engine, clock: { advance: (ms: number) => Promise<void>; settle: () => Promise<void> }, task: { toolUseId?: string; status: string; durationMs: number }, surface: 'vscode' | 'terminal' = 'vscode') {
  const ui = await $.ui.mount({
    plugin: 'xcrew',
    surface,
    component: 'UserMessage',
    requestId: 'message-1',
    props: { text: 'A background task ended.', origin: { kind: 'task-notification' }, task: { id: 'bg-1', ...task } },
  } as never)
  await ui.unmount()
  // The line is shown just after the drawing, which changes nothing itself.
  await clock.advance(1)
  await clock.settle()
}

test('a build that answers with no outcome is neither passed nor failed, and nothing is recorded', async ($, on) => {
  const { toasts, stored } = session(on)
  await callTool($, BUILD, { tool_use_id: 'toolu_bg' })
  expect(toasts).toEqual(['build_sim · no result yet, 2:55'])
  expect(stored().filter(key => /^(durations|updated|where|tests|ledger)\./.test(key))).toEqual([])
})

/** A task's "completed" means it ended, not that the build passed, so the line says neither. */
test('the notification that the call ended in the background says where its result is', async ($, on) => {
  const { toasts, clock } = session(on)
  await callTool($, BUILD, { tool_use_id: 'toolu_bg' })
  await notification($, clock, { toolUseId: 'toolu_bg', status: 'completed', durationMs: 190_000 })
  expect(toasts.at(-1)).toBe('build_sim ended in the background (3:10): its result is in the conversation')
})

test('a background task killed or failed says so', async ($, on) => {
  const { toasts, clock } = session(on)
  await callTool($, BUILD, { tool_use_id: 'toolu_bg' })
  await notification($, clock, { toolUseId: 'toolu_bg', status: 'killed', durationMs: 60_000 })
  expect(toasts.at(-1)).toBe("build_sim's background task was killed")
})

test('a notification for a call the mod read, or one naming no call, says nothing', async ($, on) => {
  const { toasts, clock } = session(on)
  await callTool($, BUILD, { tool_use_id: 'toolu_bg' })
  await notification($, clock, { toolUseId: 'toolu_other', status: 'completed', durationMs: 1_000 })
  await notification($, clock, { status: 'completed', durationMs: 1_000 })
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
  const running = callTool($, 'mcp__MobileBuildMCP__test_sim', { tool_use_id: 'toolu_live' })
  await clock.settle()
  await notification($, clock, { toolUseId: 'toolu_bg', status: 'completed', durationMs: 190_000 }, 'terminal')
  const band = await $.ui.mount({ plugin: 'xcrew', component: 'AbovePrompt', surface: 'terminal', props: { hasSurvey: false, isWorking: true, maxRows: 10, bodyColumns: 100, scroll: { offset: 0, bodyRows: 10 }, view: {} } } as never)
  expect(await band.find({ type: 'Text', text: /^test_sim/ })).toBeDefined()
  expect(await band.find({ type: 'Text', text: /ended in the background/ })).toBeUndefined()
  await band.unmount()
  release()
  await running
})
