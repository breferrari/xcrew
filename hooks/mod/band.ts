import type { ElementConstructor, RenderElement } from 'claude-code'
import type { BandProblems, BandRun } from '../../types'
import { estimate, stopwatch } from './format'

/** The band keeps showing a finished run's outcome this long. */
const HIDE_AFTER_MS = 3 * 60_000
/** The X's orange, the brand colour; everything else follows the person's theme. */
const ORANGE = '#ec501d'

/** The run while it's still going, with its phase or the time its own time began changed. */
export function changedRun(run: BandRun | null, change: Pick<BandRun, 'phase'> | Pick<BandRun, 'measuredFrom'>): BandRun | null {
  return run && !run.ended ? { ...run, ...change } : run
}

export function endedRun(run: BandRun | null, ended: NonNullable<BandRun['ended']>): BandRun | null {
  return run ? { ...run, ended } : run
}

type Segment = { text: string; color?: string; weight?: 'semibold' }

/** The band's one line, as coloured pieces. */
export function segments(run: BandRun, now: number): Segment[] {
  const target: Segment[] = run.target ? [{ text: ` · ${run.target}`, color: 'subtle' }] : []
  if (!run.ended) {
    const elapsed = now - run.startedAt
    const phase: Segment[] = run.phase ? [{ text: ` · ${run.phase}`, color: 'subtle' }] : []
    // What changes comes first, so a narrow terminal cuts the target, which the person already knows.
    return [{ text: '●', color: ORANGE }, { text: ' ' }, { text: run.tool, weight: 'semibold' }, { text: ` · ${stopwatch(elapsed)}`, color: 'subtle' }, ...(run.measuredFrom === undefined ? [] : gaugeSegments(now - run.measuredFrom, run.usual)), ...phase, ...target]
  }
  const { ok, elapsed, comparison, detail, hasFailures } = run.ended
  return [
    { text: ok ? '✓' : '✗', color: ok ? 'success' : 'error' },
    { text: ' ' },
    { text: run.tool, weight: 'semibold' },
    ...target,
    { text: ` · ${stopwatch(elapsed)}`, color: 'subtle' },
    ...(comparison ? [{ text: ` ${comparison}`, color: ORANGE }] : []),
    ...(detail ? [{ text: ` · ${detail}`, color: ok ? 'subtle' : 'error' }] : []),
    // The pane opens only when asked: docked or above the prompt, it takes room the chat needs.
    ...(hasFailures ? [{ text: ' · /xcrew failures', color: 'subtle' }] : []),
  ]
}

/** The gauge and time left, coloured: green under the usual time, the warning colour past it. */
function gaugeSegments(elapsed: number, usual: number | undefined): Segment[] {
  const parts = estimate(elapsed, usual)
  if (!parts) return []
  const tone = parts.isOver ? 'warning' : 'success'
  return [{ text: ' ' }, { text: parts.done, color: tone }, { text: parts.rest, color: 'inactive' }, { text: ` ${parts.text}`, color: parts.isOver ? 'warning' : 'subtle' }]
}

/** A finished run's line in plain text, for a toast or a notification: the band's own wording, without the target. */
export function outcomeLine(tool: string, ended: NonNullable<BandRun['ended']>): string {
  return segments({ tool, startedAt: 0, ended }, 0).map(segment => segment.text).join('')
}

/** The two elements of a `ui.render` hook's element table that this mod's trees use. */
export type Elements = { Box: ElementConstructor<any>; Text: ElementConstructor<any> }

/** Whether the band shows a run: one is going, or ended less than a few minutes ago. */
export function showsRun(run: BandRun | null, now: number): run is BandRun {
  return run !== null && !(run.ended && now - run.ended.at > HIDE_AFTER_MS)
}

/** The run above the prompt, as coloured pieces. */
export function runTree({ Box, Text }: Elements, run: BandRun, now: number): RenderElement {
  return Box({
    flexDirection: 'row',
    children: segments(run, now)
      .filter(({ text }) => text !== '')
      .map(({ text, color, weight }) => Text({ color, weight, wrap: 'truncate-end', children: [text] })),
  })
}

/** Before the first run, or once one has hidden: the doctor's most serious problem. */
export function problemsTree({ Box, Text }: Elements, problems: BandProblems): RenderElement {
  const tone = problems.isFailure ? 'error' : 'warning'
  const more = problems.more > 0 ? [Text({ color: 'subtle', children: [` (+${problems.more} more)`] })] : []
  return Box({
    flexDirection: 'row',
    children: [
      Text({ color: tone, children: ['⚠'] }),
      Text({ color: tone, wrap: 'truncate-end', children: [` ${problems.message}`] }),
      ...more,
      Text({ color: 'subtle', children: [' · /xcrew doctor'] }),
    ],
  })
}
