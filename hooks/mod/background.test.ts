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
function session(on: On) {
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
  on('session.surfaces', () => ({ value: ['vscode'] }))
  on('ui.toast', (_, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.notify', () => ({ value: { isSent: true, channel: 'terminal_bell' } }))
  on('ui.render', ($, e) => $.ui.resolve(e).Text({ children: ['as the engine draws it'] }))
  stubCli(on, { reports: [{ ok: true, isUnread: true }] })
  on('tool.call', async () => {
    await clock.advance(175_000)
    return { result: {}, text: 'Task bg-1 is running in the background.' }
  })
  return { toasts, clock, stored }
}

/**
 * The row of a background task's notification, as the engine raises it: `task` names the call that started it by its
 * `tool_use_id`, how the task ended, and how long it ran (Claude Code's types, `UserMessageTask`).
 */
async function notification($: Engine, task: { toolUseId?: string; status: string; durationMs: number }) {
  const ui = await $.ui.mount({
    plugin: 'xcrew',
    surface: 'vscode',
    component: 'UserMessage',
    requestId: 'message-1',
    props: { text: 'A background task ended.', origin: { kind: 'task-notification' }, task: { id: 'bg-1', ...task } },
  } as never)
  await ui.unmount()
}

test('a build that answers with no outcome is neither passed nor failed, and nothing is recorded', async ($, on) => {
  const { toasts, stored } = session(on)
  await callTool($, BUILD, { tool_use_id: 'toolu_bg' })
  expect(toasts).toEqual(['build_sim · no result yet, 2:55'])
  expect(stored().filter(key => /^(durations|updated|where|tests|ledger)\./.test(key))).toEqual([])
})

/** A task's "completed" means it ended, not that the build passed, so the line says neither. */
test('the notification that the call ended in the background says where its result is', async ($, on) => {
  const { toasts } = session(on)
  await callTool($, BUILD, { tool_use_id: 'toolu_bg' })
  await notification($, { toolUseId: 'toolu_bg', status: 'completed', durationMs: 190_000 })
  expect(toasts.at(-1)).toBe('build_sim ended in the background (3:10): its result is in the conversation')
})

test('a background task killed or failed says so', async ($, on) => {
  const { toasts } = session(on)
  await callTool($, BUILD, { tool_use_id: 'toolu_bg' })
  await notification($, { toolUseId: 'toolu_bg', status: 'killed', durationMs: 60_000 })
  expect(toasts.at(-1)).toBe("build_sim's background task was killed")
})

test('a notification for a call the mod read, or one naming no call, says nothing', async ($, on) => {
  const { toasts } = session(on)
  await callTool($, BUILD, { tool_use_id: 'toolu_bg' })
  await notification($, { toolUseId: 'toolu_other', status: 'completed', durationMs: 1_000 })
  await notification($, { status: 'completed', durationMs: 1_000 })
  expect(toasts).toEqual(['build_sim · no result yet, 2:55'])
})
