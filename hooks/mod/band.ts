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

/** A piece of the line in the theme's text colour, unless `color` names another. */
function segment(text: string, color?: string, weight?: 'semibold'): Segment {
  return { text, ...(color ? { color } : {}), ...(weight ? { weight } : {}) }
}

/** The faint ` · ` between pieces. Only separators are faint: the values read in the theme's own text colour. */
const SEPARATOR = segment(' · ', 'subtle')

/** A value after its separator; the band draws the two as one text, so a narrow terminal cuts them together. */
function piece(text: string, color?: string): Segment[] {
  return [SEPARATOR, segment(text, color)]
}

/** The band's one line, as coloured pieces. What changes comes first, so a narrow terminal cuts the target last. */
export function segments(run: BandRun, now: number): Segment[] {
  const target = run.target ? piece(run.target) : []
  if (!run.ended) {
    const elapsed = now - run.startedAt
    const phase = run.phase ? piece(run.phase) : []
    return [segment('●', ORANGE), segment(' '), segment(run.tool, undefined, 'semibold'), ...piece(stopwatch(elapsed)), ...(run.measuredFrom === undefined ? [] : gaugeSegments(now - run.measuredFrom, run.usual)), ...phase, ...target]
  }
  const { ok, elapsed, comparison, detail, hasFailures } = run.ended
  return [
    segment(ok ? '✓' : '✗', ok ? 'success' : 'error'),
    segment(' '),
    segment(run.tool, undefined, 'semibold'),
    ...piece(stopwatch(elapsed)),
    ...(comparison ? [segment(' '), segment(comparison, ORANGE)] : []),
    ...(detail ? piece(detail, ok ? undefined : 'error') : []),
    // The pane opens only when asked: docked or above the prompt, it takes room the chat needs.
    ...(hasFailures ? piece('/xcrew failures') : []),
    ...target,
  ]
}

/** The gauge and time left: green under the usual time, the warning colour past it, the time left in the text colour. */
function gaugeSegments(elapsed: number, usual: number | undefined): Segment[] {
  const parts = estimate(elapsed, usual)
  if (!parts) return []
  return [segment(' '), segment(parts.done, parts.isOver ? 'warning' : 'success'), segment(parts.rest, 'inactive'), segment(' '), segment(parts.text, parts.isOver ? 'warning' : undefined)]
}

/** The doctor's most serious problem, as the same pieces as a run. */
function problemSegments(problems: BandProblems): Segment[] {
  const tone = problems.isFailure ? 'error' : 'warning'
  return [segment('⚠', tone), segment(' '), segment(problems.message, tone), ...(problems.more > 0 ? [segment(' '), segment(`(+${problems.more} more)`, 'subtle')] : []), ...piece('/xcrew doctor')]
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

/** A row of pieces, each separator drawn inside its value's text. */
function line({ Box, Text }: Elements, parts: Segment[]): RenderElement {
  const children: RenderElement[] = []
  for (let index = 0; index < parts.length; index += 1) {
    const part = parts[index]
    if (!part || part.text === '') continue
    const value = part === SEPARATOR ? parts[index + 1] : undefined
    if (value) {
      index += 1
      children.push(Text({ wrap: 'truncate-end', children: [Text({ color: part.color, children: [part.text] }), Text({ color: value.color, weight: value.weight, children: [value.text] })] }))
    } else {
      children.push(Text({ color: part.color, weight: part.weight, wrap: 'truncate-end', children: [part.text] }))
    }
  }
  return Box({ flexDirection: 'row', children })
}

/** The run above the prompt. */
export function runTree(elements: Elements, run: BandRun, now: number): RenderElement {
  return line(elements, segments(run, now))
}

/** Before the first run, or once one has hidden: the doctor's most serious problem. */
export function problemsTree(elements: Elements, problems: BandProblems): RenderElement {
  return line(elements, problemSegments(problems))
}
