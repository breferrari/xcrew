import type { EngineInterface, On } from 'claude-code'
import { average, comparison, estimate, stopwatch } from './format'
import { clearRun, endRun, outcomeLine, startRun, updateRun } from './band'
import { describe, historyOf, observe } from './context'
import { phase as readRunPhase, report } from './cli'
import { recordRun } from './failures'
import { kindOf, parseTool } from './tools'

/** How many earlier runs of each tool the average covers. */
export const HISTORY = 10
export const DURATIONS_PREFIX = 'durations.'
const historyKey = (tool: string) => `${DURATIONS_PREFIX}${tool}`
/** The last test run's total per tool, for the next run's `testing 312 of 959`. */
const testsKey = (tool: string) => `tests.${tool}`
/** Whether a tool has written a log before: those say they're preparing until this run's appears; `clean` writes none. */
const logsKey = (tool: string) => `logs.${tool}`
const PREPARING = 'preparing'
/** Runs at least this long also send a notification. */
const LONG_RUN_MS = 60_000

/** Bookkeeping is best-effort: a clock, store or display failure must never fail a build. */
async function quietly<T>(work: () => Promise<T> | T): Promise<T | undefined> {
  try {
    return await work()
  } catch {
    return undefined
  }
}

/** The status line's gauge, the band's in plain text: ` ━━━━╸─── ~0:15 left`. */
function plainEstimate(elapsed: number, usual: number | undefined): string {
  const parts = estimate(elapsed, usual)
  return parts ? ` ${parts.done}${parts.rest} ${parts.text}` : ''
}

/**
 * Times builds, test runs and app runs: the band counts while one runs and then shows its outcome
 * and how it compares with the last runs of the same tool. Where no band draws, the status line
 * counts and a toast reports the outcome. A long run also notifies.
 */
export function registerTiming(on: On): void {
  on('tool.call', async ($, e, next) => {
    const parsed = parseTool(e.tool)
    if (!parsed) return next(e)
    const name = parsed.tool
    const kind = kindOf(parsed)
    if (!kind) {
      // Not timed, but its answer may say what the next build will use.
      const result = await next(e)
      observe(parsed, result.text ?? '')
      return result
    }
    const target = describe(parsed, e as unknown as Record<string, unknown>)
    const label = target ? `${name} · ${target}` : `${name} running`
    // Durations and test totals are kept per scheme and test selection, not only per tool.
    const history = historyOf(parsed, e as unknown as Record<string, unknown>)

    const started = await quietly(() => $.clock.now())
    const earlier = ((await quietly(() => $.store.get(historyKey(history)))) as number[] | undefined) ?? []
    // What the gauge measures against; a tool's first run has none and shows its time alone.
    const usual = earlier.length > 0 ? average(earlier) : undefined
    // The band draws in colour where a surface can show it; elsewhere the plain status line carries the run.
    const surfaces = (await quietly(() => $.session.surfaces())) ?? []
    const usesBand = surfaces.some(surface => surface === 'terminal' || surface === 'desktop')
    // MobileBuildMCP logs xcodebuild's output as the run goes; the Xcode MCP writes nothing to follow.
    const followsLog = parsed.server === 'MobileBuildMCP'
    const expectedTests = followsLog ? ((await quietly(() => $.store.get(testsKey(history)))) as number | undefined) : undefined
    const writesLog = followsLog && (await quietly(() => $.store.get(logsKey(name)))) === true
    // The usual time is the server's own, which leaves out a pre-build hook; for a tool that logs,
    // the gauge starts when the log appears, before which the run itself hasn't begun.
    let measuredFrom = writesLog ? undefined : started
    let logPath: string | undefined
    if (usesBand && started !== undefined) await quietly(() => startRun($, { tool: name, target, startedAt: started, ...(usual === undefined ? {} : { usual }), ...(measuredFrom === undefined ? {} : { measuredFrom }) }))
    let phase: string | undefined
    const readPhase = async (since: number) => {
      const found = (await quietly(() => readRunPhase($, name, since, expectedTests, logPath))) ?? {}
      if (logPath === undefined && found.log !== undefined) {
        logPath = found.log
        if (!writesLog) await quietly(() => $.store.set(logsKey(name), true))
        if (measuredFrom === undefined) {
          measuredFrom = await quietly(() => $.clock.now())
          const from = measuredFrom
          if (usesBand && from !== undefined) await quietly(() => updateRun($, { measuredFrom: from }))
        }
      }
      // Before its log appears xcodebuild hasn't started: a pre-build hook, a permission prompt or the server's own preparation.
      const now = found.phase ?? (writesLog && logPath === undefined ? PREPARING : undefined)
      if (now === undefined || now === phase) return
      phase = now
      if (usesBand) await quietly(() => updateRun($, { phase: now }))
    }
    const ticker = started === undefined ? undefined : await quietly(() =>
      $.clock.every(1000, async () => {
        if (followsLog) await readPhase(started)
        if (usesBand) return quietly(() => $.ui.invalidate('ui.render'))
        const now = await quietly(() => $.clock.now())
        if (now !== undefined) await quietly(() => $.ui.status(`${label} · ${stopwatch(now - started)}${measuredFrom === undefined ? '' : plainEstimate(now - measuredFrom, usual)}${phase ? ` · ${phase}` : ''}`))
      }),
    )

    const result = await next(e)

    ticker?.cancel()
    if (!usesBand) await quietly(() => $.ui.status(undefined))
    const ended = await quietly(() => $.clock.now())
    if (started === undefined || ended === undefined) return result
    // A denied call never ran: it has no outcome to show and no time that says how long a run takes.
    if (result.deny !== undefined) {
      if (usesBand) await quietly(() => clearRun($))
      return result
    }

    // The CLI reads the server's output: the outcome, the failures, the duration it reports, and what Claude reads.
    // `report` never throws: without the CLI it falls back to whether the server reported an error.
    const outcome = await report($, parsed.server, kind, result.text ?? '', result.isError === true)
    // The server's own duration leaves out what ran around the call: a project's pre-build hook, a permission prompt.
    const elapsed = outcome.durationMs ?? ended - started
    await quietly(() => $.store.set(historyKey(history), [...earlier, elapsed].slice(-HISTORY)))
    await quietly(() => recordRun($, history, outcome.ok, outcome.failures))
    if (outcome.tests !== undefined) await quietly(() => $.store.set(testsKey(history), outcome.tests))
    const compared = comparison(elapsed, earlier)
    const ending = { at: ended, elapsed, ok: outcome.ok, detail: outcome.detail, comparison: compared, hasFailures: !outcome.ok && outcome.failures.length > 0 }
    const summary = outcomeLine(name, ending)
    if (usesBand) {
      await quietly(() => endRun($, ending))
    } else {
      // The band stays up with this same line where it draws; elsewhere a toast carries it.
      await quietly(() => $.ui.toast(summary))
    }
    // Long enough that the person has likely looked away; their notification settings decide how it arrives.
    if (elapsed >= LONG_RUN_MS) await quietly(() => $.ui.notify(summary))
    if (result.deny !== undefined) return result
    const context = outcome.notes.length > 0 ? { context: [...(result.context ?? []), ...outcome.notes] } : {}
    // Its own `result`, without core's `ref`: with `ref` kept, core shows the model its own messages.
    if (outcome.result !== undefined) return result.isError ? { result: outcome.result, isError: true, ...context } : { result: outcome.result, ...context }
    return { ...result, ...context }
  })
}
