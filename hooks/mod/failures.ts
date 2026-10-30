import type { RenderElement } from 'claude-code'
import type { FailureList } from '../../types'
import type { Elements } from './band'
import type { Failure } from './cli'

const NONE = 'No failures in the last runs.'

/**
 * What a finished run leaves in the pane. `run` is the tool with its scheme and test selection
 * (`test_sim · App › AppTests`): only a passing run of that same scope clears the failures, since
 * another scheme's or selection's pass never re-ran them. Clearing closes the pane. A run the Mac
 * failed (`cause`) leaves its cause even when it lists no failure.
 */
export function afterRun(list: FailureList | null, run: string, ok: boolean, items: Failure[], cause?: string): { list: FailureList | null; closesPane: boolean } {
  if (ok) return list?.tool === run ? { list: null, closesPane: true } : { list, closesPane: false }
  return { list: items.length > 0 || cause !== undefined ? { tool: run, items, cause } : list, closesPane: false }
}

/** What the pane holds, in one line. */
export function summary(list: FailureList | null): string {
  if (!list) return NONE
  const count = list.items.length
  if (count === 0) return `The Mac's cause from ${list.tool}, in the pane.`
  return `${count} ${count === 1 ? 'failure' : 'failures'} from ${list.tool}, in the pane${list.cause === undefined ? '' : ", after the Mac's cause"}.`
}

/**
 * The Mac's cause first, when the run has one, so the person sees what Claude read; then each failure: its test or file in
 * the error colour, where it failed, and its message, then the paths of its images.
 */
export function paneTree({ Box, Text }: Elements, list: FailureList | null): RenderElement {
  if (!list) return Box({ children: [Text({ color: 'subtle', children: [NONE] })] })
  const cause = list.cause === undefined ? [] : [Text({ color: 'warning', children: [list.cause] })]
  return Box({
    flexDirection: 'column',
    children: [
      ...cause,
      ...list.items.flatMap((item, index) => [
        ...(index > 0 || cause.length > 0 ? [Text({ children: [' '] })] : []),
        Text({ color: 'error', weight: 'semibold', children: [item.title] }),
        ...(item.where ? [Text({ color: 'subtle', children: [item.where] })] : []),
        Text({ children: [item.message] }),
        ...[...(item.images ?? []), ...(item.moreImages ? [item.moreImages] : [])].map(line => Text({ color: 'subtle', children: [line] })),
      ]),
    ],
  })
}
