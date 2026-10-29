import type { BandRun } from '../../types'
import type { Report } from './cli'
import { comparison, estimate, stopwatch } from './format'

/**
 * Timing's arithmetic and words, for the hook in the hooks module that times builds, test runs and
 * app runs: the band counts while one runs and then shows its outcome and how it compares with the
 * last runs of the same tool. Where no band draws, the status line counts and a toast reports the
 * outcome. A long run also notifies.
 */

/** How many earlier runs of each tool the average covers. */
export const HISTORY = 10
export const DURATIONS_PREFIX = 'durations.'
export const historyKey = (tool: string) => `${DURATIONS_PREFIX}${tool}`
/** The last test run's total per tool, for the next run's `testing 312 of 959`. */
export const testsKey = (tool: string) => `tests.${tool}`
/** Whether a tool has written a log before: those say they're preparing until this run's appears; `clean` writes none. */
export const logsKey = (tool: string) => `logs.${tool}`
export const PREPARING = 'preparing'
/** Runs at least this long also send a notification. */
export const LONG_RUN_MS = 60_000

/** Bookkeeping is best-effort: a clock, store or display failure must never fail a build. */
export async function quietly<T>(work: () => Promise<T> | T): Promise<T | undefined> {
  try {
    return await work()
  } catch {
    return undefined
  }
}

/** The band draws in colour where a surface can show it; elsewhere the plain status line carries the run. */
export function drawsBand(surfaces: readonly string[]): boolean {
  return surfaces.some(surface => surface === 'terminal' || surface === 'desktop')
}

export function labelOf(tool: string, target: string | undefined): string {
  return target ? `${tool} · ${target}` : `${tool} running`
}

/** The status line's gauge, the band's in plain text: ` ━━━━╸─── ~0:15 left`. */
function plainEstimate(elapsed: number, usual: number | undefined): string {
  const parts = estimate(elapsed, usual)
  return parts ? ` ${parts.done}${parts.rest} ${parts.text}` : ''
}

/** The status line while a run goes, where no band draws. */
export function statusLine(label: string, started: number, now: number, measuredFrom: number | undefined, usual: number | undefined, phase: string | undefined): string {
  return `${label} · ${stopwatch(now - started)}${measuredFrom === undefined ? '' : plainEstimate(now - measuredFrom, usual)}${phase ? ` · ${phase}` : ''}`
}

/** What a running call's log has told the hook so far. */
export type Following = { logPath?: string; phase?: string }

/**
 * What the hook does with what `xcrew phase` found: keep the log once it appears, and with it start
 * the gauge if it waited for the log; and show a phase that changed. Before its log appears xcodebuild
 * hasn't started (a pre-build hook, a permission prompt or the server's own preparation), so a tool
 * that writes one says it's preparing.
 */
export function phaseStep(following: Following, found: { log?: string; phase?: string }, writesLog: boolean): { following: Following; logAppeared: boolean; newPhase?: string } {
  const logAppeared = following.logPath === undefined && found.log !== undefined
  const logPath = logAppeared ? found.log : following.logPath
  const now = found.phase ?? (writesLog && logPath === undefined ? PREPARING : undefined)
  const newPhase = now !== undefined && now !== following.phase ? now : undefined
  return { following: { logPath, phase: newPhase ?? following.phase }, logAppeared, ...(newPhase === undefined ? {} : { newPhase }) }
}

/** A finished run's ending, for the band and the outcome line. */
export function endingOf(outcome: Report, at: number, elapsed: number, earlier: readonly number[]): NonNullable<BandRun['ended']> {
  return { at, elapsed, ok: outcome.ok, detail: outcome.detail, comparison: comparison(elapsed, earlier), hasFailures: !outcome.ok && outcome.failures.length > 0 }
}

/**
 * What Claude reads: the CLI's shorter result and notes in place of the server's. Its own `result`,
 * without core's `ref`: with `ref` kept, core shows the model its own messages.
 */
export function resultFor<Result extends { context?: readonly string[]; isError?: unknown }>(result: Result, outcome: Report) {
  const context = outcome.notes.length > 0 ? { context: [...(result.context ?? []), ...outcome.notes] } : {}
  if (outcome.result !== undefined) return result.isError ? { result: outcome.result, isError: true as const, ...context } : { result: outcome.result, ...context }
  return { ...result, ...context }
}
