import type { ElementConstructor, RenderElement } from 'claude-code'
import type { BandProblems, BandRun, ResultRow } from '../../types'
import { estimate, stopwatch } from './format'

/** How long a finished run stays on the band: a pass asks for nothing, a failure asks to be looked at. */
export const PASSED_FOR_MS = 3 * 60_000
export const FAILED_FOR_MS = 30 * 60_000
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

/** The band's one line, as coloured pieces: the run's outcome or progress, then what's for the prompt. What changes
 * comes first, so a narrow terminal cuts the target last. */
export function segments(run: BandRun, now: number): Segment[] {
  return [...outcomeSegments(run, now), ...pointer(run.ended), ...(run.target ? piece(run.target) : [])]
}

/** The run alone: going, with its time, gauge and phase, or ended, with its outcome. */
function outcomeSegments(run: BandRun, now: number): Segment[] {
  if (run.ended) return endedSegments(run.tool, run.ended)
  const elapsed = now - run.startedAt
  const phase = run.phase ? piece(run.phase) : []
  return [segment('●', ORANGE), segment(' '), segment(run.tool, undefined, 'semibold'), ...piece(stopwatch(elapsed)), ...(run.measuredFrom === undefined ? [] : gaugeSegments(now - run.measuredFrom, run.usual)), ...phase]
}

/** A finished run's outcome: the mark, the tool, its time and how it compares, and what it came to. */
function endedSegments(tool: string, ended: NonNullable<BandRun['ended']>): Segment[] {
  const { ok, elapsed, comparison, detail } = ended
  // Neither passed nor failed: no mark, and no colour that reads as either.
  if (ended.background) return [segment(tool, undefined, 'semibold'), segment(backgroundNote(ended.background.status, ended.background.durationMs))]
  if (ended.isUnread) return [segment(tool, undefined, 'semibold'), ...piece(`no result yet, ${stopwatch(elapsed)}`)]
  return [
    segment(ok ? '✓' : '✗', ok ? 'success' : 'error'),
    segment(' '),
    segment(tool, undefined, 'semibold'),
    ...piece(stopwatch(elapsed)),
    ...(comparison ? [segment(' '), segment(comparison, ORANGE)] : []),
    ...(detail ? piece(detail, ok ? undefined : 'error') : []),
  ]
}

/** Where a failing run's failures are: a command for the prompt, so only lines beside one carry it. The pane opens
 * only when asked: docked or above the prompt, it takes room the chat needs. */
function pointer(ended: BandRun['ended']): Segment[] {
  return ended?.hasFailures ? piece('/xcrew failures') : []
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

/** A finished run's outcome in plain text, for a notification, which arrives where no command can be typed. */
export function outcomeLine(tool: string, ended: NonNullable<BandRun['ended']>): string {
  return text(endedSegments(tool, ended))
}

/** The outcome with the pointer to its failures, for a toast, which sits beside the prompt where no band draws. */
export function promptLine(tool: string, ended: NonNullable<BandRun['ended']>): string {
  return text([...endedSegments(tool, ended), ...pointer(ended)])
}

function text(parts: Segment[]): string {
  return parts.map(part => part.text).join('')
}

/** The two elements of a `ui.render` hook's element table that this mod's trees use. */
export type Elements = { Box: ElementConstructor<any>; Text: ElementConstructor<any> }

export function shownFor(ended: NonNullable<BandRun['ended']>): number {
  return ended.ok ? PASSED_FOR_MS : FAILED_FOR_MS
}

/** Whether the band shows a run: one is going, or ended within the time its outcome stays. */
export function showsRun(run: BandRun | null, now: number): run is BandRun {
  return run !== null && !(run.ended && now - run.ended.at > shownFor(run.ended))
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

/** A finished run's row in the transcript: its outcome as the band drew it, then its first failures and how many more.
 * No `/xcrew failures` here: the pane holds the latest failing run's, and a row stays in the transcript after the next. */
export function resultTree(elements: Elements, tool: string, row: ResultRow): RenderElement {
  const failures = row.failures.map(failure => line(elements, [segment('✗', 'error'), segment(' '), segment(failure.title), ...(failure.where ? piece(failure.where) : [])]))
  const more = row.more > 0 ? [line(elements, [segment(`${row.more} more`, 'subtle')])] : []
  return elements.Box({ flexDirection: 'column', children: [line(elements, endedSegments(tool, row.ended)), ...failures, ...more] })
}

/** The doctor's most serious problem: a pending restart over a finished run, anything else while no run shows. */
export function problemsTree(elements: Elements, problems: BandProblems): RenderElement {
  return line(elements, problemSegments(problems))
}

/**
 * What a background task's notification says of the call that started it, after its name. The task ending
 * (`completed`) isn't the build passing, so that reads as neither; only a task failed or killed says how it ended.
 */
export function backgroundNote(status: string | undefined, durationMs: number | undefined): string {
  if (status === 'failed' || status === 'killed') return `'s background task was ${status}`
  return ` ended in the background${durationMs === undefined ? '' : ` (${stopwatch(durationMs)})`}: its result is in the conversation`
}
