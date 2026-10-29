import { atom, read, update } from 'claude-code'
import type { EngineInterface, On } from 'claude-code'
import type { FailureList } from '../../types'
import type { Failure } from './cli'

export const FAILURES_PANE = 'xcrew-failures'
const NONE = 'No failures in the last runs.'

const failuresState = atom({ plugin: 'xcrew', key: 'failures' } as const, null as FailureList | null)

/**
 * Whether the terminal docks a pane beside the transcript, as the band last drew. A drawing can't
 * write `$.state`, and the layout is fixed for the session, so a reload's next draw sets it again.
 */
let isFullscreen: boolean | undefined

export function noteLayout(viewport: { isFullscreen?: boolean } | undefined): void {
  isFullscreen = viewport?.isFullscreen
}

/**
 * Keeps the last failing run's failures for the session. `run` is the tool with its scheme and
 * test selection (`test_sim · App › AppTests`): only a passing run of that same scope clears them,
 * since another scheme's or selection's pass never re-ran them. Clearing closes the pane. A failure
 * opens it in the fullscreen layout, where it docks beside the chat; on the main screen it would take
 * over the space above the prompt, so there it waits for `/xcrew failures`.
 */
export async function recordRun($: EngineInterface, run: string, ok: boolean, items: Failure[]): Promise<void> {
  if (ok) {
    const list = await read($, failuresState)
    if (list?.tool !== run) return
    await update($, failuresState, () => null)
    await $.ui.close({ id: FAILURES_PANE })
    return
  }
  if (items.length === 0) return
  await update($, failuresState, () => ({ tool: run, items }))
  if (isFullscreen === true) await $.ui.open({ id: FAILURES_PANE, title: 'Failures' })
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
