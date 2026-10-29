import { atom, read, update } from 'claude-code'
import type { EngineInterface, On } from 'claude-code'
import type { FailureList } from '../../types'
import type { Failure } from './cli'

export const FAILURES_PANE = 'xcrew-failures'
const NONE = 'No failures in the last runs.'

const failuresState = atom({ plugin: 'xcrew', key: 'failures' } as const, null as FailureList | null)

/**
 * Keeps the last failing run's failures for the session. `run` is the tool with its scheme and
 * test selection (`test_sim · App › AppTests`): only a passing run of that same scope clears them,
 * since another scheme's or selection's pass never re-ran them. Clearing closes the pane.
 */
export async function recordRun($: EngineInterface, run: string, ok: boolean, items: Failure[]): Promise<void> {
  if (ok) {
    const list = await read($, failuresState)
    if (list?.tool !== run) return
    await update($, failuresState, () => null)
    await $.ui.close({ id: FAILURES_PANE })
    return
  }
  if (items.length > 0) await update($, failuresState, () => ({ tool: run, items }))
}

/** Opens the pane and says, in one line, what it holds. */
export async function openFailures($: EngineInterface): Promise<string> {
  await $.ui.open({ id: FAILURES_PANE, title: 'Failures' })
  const list = await read($, failuresState)
  if (!list) return NONE
  const count = list.items.length
  return `${count} ${count === 1 ? 'failure' : 'failures'} from ${list.tool}, in the pane.`
}

/** In Claude Code's default layout the pane's close mark can't be clicked; this closes it from the prompt. */
export async function closeFailures($: EngineInterface): Promise<string> {
  await $.ui.close({ id: FAILURES_PANE })
  return 'Closed the failures pane.'
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
