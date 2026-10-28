import { atom, read, update } from 'claude-code'
import type { EngineInterface, On } from 'claude-code'
import type { BandRun } from '../../types'
import { gauge, remaining, stopwatch } from './format'

/** The band keeps showing a finished run's outcome this long. */
const HIDE_AFTER_MS = 3 * 60_000
/** Cells in the gauge: wide enough to move each few seconds, narrow enough to leave room for the rest. */
const GAUGE_CELLS = 8
/** The X's orange, the brand colour; everything else follows the person's theme. */
const ORANGE = '#ec501d'

export const runState = atom({ plugin: 'xcrew', key: 'run' } as const, null as BandRun | null)

export function startRun($: EngineInterface, run: BandRun): Promise<unknown> {
  return update($, runState, () => run)
}

export function setPhase($: EngineInterface, phase: string): Promise<unknown> {
  return update($, runState, run => (run && !run.ended ? { ...run, phase } : run))
}

export function endRun($: EngineInterface, ended: NonNullable<BandRun['ended']>): Promise<unknown> {
  return update($, runState, run => (run ? { ...run, ended } : run))
}

type Segment = { text: string; color?: string; weight?: 'semibold' }

/** The band's one line, as coloured pieces. */
export function segments(run: BandRun, now: number): Segment[] {
  const target: Segment[] = run.target ? [{ text: ` · ${run.target}`, color: 'subtle' }] : []
  if (!run.ended) {
    const elapsed = now - run.startedAt
    const phase: Segment[] = run.phase ? [{ text: ` · ${run.phase}`, color: 'subtle' }] : []
    // What changes comes first, so a narrow terminal cuts the target, which the person already knows.
    return [{ text: '●', color: ORANGE }, { text: ' ' }, { text: run.tool, weight: 'semibold' }, { text: ` · ${stopwatch(elapsed)}`, color: 'subtle' }, ...estimate(elapsed, run.usual), ...phase, ...target]
  }
  const { ok, elapsed, comparison, detail } = run.ended
  return [
    { text: ok ? '✓' : '✗', color: ok ? 'success' : 'error' },
    { text: ' ' },
    { text: run.tool, weight: 'semibold' },
    ...target,
    { text: ` · ${stopwatch(elapsed)}`, color: 'subtle' },
    ...(comparison ? [{ text: ` ${comparison}`, color: ORANGE }] : []),
    ...(detail ? [{ text: ` · ${detail}`, color: ok ? 'subtle' : 'error' }] : []),
  ]
}

/** A gauge of the time so far against the usual time, and how much is left; nothing without a usual time. */
function estimate(elapsed: number, usual: number | undefined): Segment[] {
  if (usual === undefined || usual <= 0) return []
  const { done, rest } = gauge(elapsed / usual, GAUGE_CELLS)
  const { text, isOver } = remaining(elapsed, usual)
  const tone = isOver ? 'warning' : 'success'
  return [{ text: ' ' }, { text: done, color: tone }, { text: rest, color: 'inactive' }, { text: ` ${text}`, color: isOver ? 'warning' : 'subtle' }]
}

/** Draws the run above the prompt, and nothing when there's none or it ended a while ago. */
export function registerBand(on: On): void {
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const run = await read($, runState)
    if (!run) return next(e)
    const now = await $.clock.now()
    if (run.ended && now - run.ended.at > HIDE_AFTER_MS) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    return Box({
      flexDirection: 'row',
      children: segments(run, now)
        .filter(({ text }) => text !== '')
        .map(({ text, color, weight }) => Text({ color, weight, wrap: 'truncate-end', children: [text] })),
    })
  })
}
