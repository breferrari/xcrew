import type { RenderElement } from 'claude-code'
import type { FailureList } from '../../types'
import type { Elements } from './band'
import type { Failure } from './cli'

const NONE = 'No failures in the last runs.'

/**
 * What a finished run leaves in the pane. `run` is the tool with its scheme and test selection
 * (`test_sim · App › AppTests`): only a passing run of that same scope clears the failures, since
 * another scheme's or selection's pass never re-ran them. Clearing closes the pane.
 */
export function afterRun(list: FailureList | null, run: string, ok: boolean, items: Failure[]): { list: FailureList | null; closesPane: boolean } {
  if (ok) return list?.tool === run ? { list: null, closesPane: true } : { list, closesPane: false }
  return { list: items.length > 0 ? { tool: run, items } : list, closesPane: false }
}

/** What the pane holds, in one line. */
export function summary(list: FailureList | null): string {
  if (!list) return NONE
  const count = list.items.length
  return `${count} ${count === 1 ? 'failure' : 'failures'} from ${list.tool}, in the pane.`
}

/** Each failure: its test or file in the error colour, where it failed, and its message, then the paths of its images. */
export function paneTree({ Box, Text }: Elements, list: FailureList | null): RenderElement {
  if (!list) return Box({ children: [Text({ color: 'subtle', children: [NONE] })] })
  return Box({
    flexDirection: 'column',
    children: list.items.flatMap((item, index) => [
      ...(index > 0 ? [Text({ children: [' '] })] : []),
      Text({ color: 'error', weight: 'semibold', children: [item.title] }),
      ...(item.where ? [Text({ color: 'subtle', children: [item.where] })] : []),
      Text({ children: [item.message] }),
      ...[...(item.images ?? []), ...(item.moreImages ? [item.moreImages] : [])].map(line => Text({ color: 'subtle', children: [line] })),
    ]),
  })
}
