import { atom, read, update } from 'claude-code'
import type { EngineInterface, On } from 'claude-code'
import type { BandRun } from '../../types'
import { stopwatch } from './format'

/** The band keeps showing a finished run's outcome this long. */
const HIDE_AFTER_MS = 3 * 60_000
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
    const phase: Segment[] = run.phase ? [{ text: ` · ${run.phase}`, color: 'subtle' }] : []
    return [{ text: '●', color: ORANGE }, { text: ' ' }, { text: run.tool, weight: 'semibold' }, ...target, { text: ` · ${stopwatch(now - run.startedAt)}`, color: 'subtle' }, ...phase]
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
      children: segments(run, now).map(({ text, color, weight }) => Text({ color, weight, wrap: 'truncate-end', children: [text] })),
    })
  })
}
