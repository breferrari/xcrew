import { atom, read, update } from 'claude-code'
import type { EngineInterface, On } from 'claude-code'
import type { FailureList } from '../../types'
import { failuresOf } from './results'

export const FAILURES_PANE = 'xcrew-failures'
const NONE = 'No failures in the last runs.'

const failuresState = atom({ plugin: 'xcrew', key: 'failures' } as const, null as FailureList | null)

/**
 * Keeps the last failing run's failures for the session. A later passing run of the same tool
 * clears them; another tool's passing run leaves them, since they're still unfixed.
 */
export function recordRun($: EngineInterface, tool: string, ok: boolean, text: string): Promise<unknown> {
  if (ok) return update($, failuresState, list => (list?.tool === tool ? null : list))
  const items = failuresOf(text)
  return items.length === 0 ? Promise.resolve() : update($, failuresState, () => ({ tool, items }))
}

/** Opens the pane and says, in one line, what it holds. */
export async function openFailures($: EngineInterface): Promise<string> {
  await $.ui.open({ id: FAILURES_PANE, title: 'Failures' })
  const list = await read($, failuresState)
  if (!list) return NONE
  const count = list.items.length
  return `${count} ${count === 1 ? 'failure' : 'failures'} from ${list.tool}, in the pane.`
}

/** Each failure: its test or file in the error colour, where it failed, and its message. */
export function registerFailures(on: On): void {
  on('ui.render', { component: 'Pane', requestId: FAILURES_PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const list = await read($, failuresState)
    if (!list) return Box({ children: [Text({ color: 'subtle', children: [NONE] })] })
    return Box({
      flexDirection: 'column',
      children: list.items.flatMap((item, index) => [
        ...(index > 0 ? [Text({ children: [' '] })] : []),
        Text({ color: 'error', weight: 'semibold', children: [item.title] }),
        ...(item.where ? [Text({ color: 'subtle', children: [item.where] })] : []),
        Text({ children: [item.message] }),
      ]),
    })
  })
}
