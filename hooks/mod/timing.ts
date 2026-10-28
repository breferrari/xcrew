import type { EngineInterface, On } from 'claude-code'
import { average, comparison, gauge, remaining, stopwatch } from './format'
import { endRun, setPhase, startRun } from './band'
import { describe, observe, scopeOf } from './context'
import { recordRun } from './failures'
import { phaseOf, findRunLog } from './progress'
import { reportedDuration, summarize, testTotal } from './results'
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

/** Claude Code's notice for a result over its size limit, naming the file that holds the whole text. */
const SAVED_RESULT = /Output has been saved to (\/\S+\/tool-results\/\S+?)\.\s/

/** The text to judge a result by: a result Claude Code saved to a file is read back from it. */
async function fullText($: EngineInterface, text: string): Promise<string> {
  const saved = SAVED_RESULT.exec(text)?.[1]
  if (!saved) return text
  return (await quietly(() => $.fs.read(saved))) ?? text
}

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
  if (usual === undefined || usual <= 0) return ''
  const { done, rest } = gauge(elapsed / usual, 8)
  return ` ${done}${rest} ${remaining(elapsed, usual).text}`
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
    if (!kindOf(parsed)) {
      // Not timed, but its answer may say what the next build will use.
      const result = await next(e)
      observe(parsed, result.text ?? '')
      return result
    }
    const name = parsed.tool
    const target = describe(parsed, e as unknown as Record<string, unknown>)
    const label = target ? `${name} · ${target}` : `${name} running`
    const scope = scopeOf(parsed, e as unknown as Record<string, unknown>)
    // Durations and test totals are kept per scheme and test selection, not only per tool.
    const history = scope ? `${name} · ${scope}` : name

    const started = await quietly(() => $.clock.now())
    const earlier = ((await quietly(() => $.store.get(historyKey(history)))) as number[] | undefined) ?? []
    // What the gauge measures against; a tool's first run has none and shows its time alone.
    const usual = earlier.length > 0 ? average(earlier) : undefined
    // The band draws in colour where a surface can show it; elsewhere the plain status line carries the run.
    const surfaces = (await quietly(() => $.session.surfaces())) ?? []
    const usesBand = surfaces.some(surface => surface === 'terminal' || surface === 'desktop')
    if (usesBand && started !== undefined) await quietly(() => startRun($, { tool: name, target, startedAt: started, usual }))
    // MobileBuildMCP logs xcodebuild's output as the run goes; the Xcode MCP writes nothing to follow.
    const followsLog = parsed.server === 'MobileBuildMCP'
    const expectedTests = followsLog ? ((await quietly(() => $.store.get(testsKey(history)))) as number | undefined) : undefined
    const writesLog = followsLog && (await quietly(() => $.store.get(logsKey(name)))) === true
    let logPath: string | undefined
    let phase: string | undefined
    const readPhase = async (since: number) => {
      if (logPath === undefined) {
        logPath = await quietly(() => findRunLog($, name, since))
        if (logPath !== undefined && !writesLog) await quietly(() => $.store.set(logsKey(name), true))
      }
      const log = logPath === undefined ? undefined : await quietly(() => $.fs.read(logPath as string))
      // Before its log appears xcodebuild hasn't started: a pre-build hook, a permission prompt or the server's own preparation.
      const now = typeof log === 'string' ? phaseOf(log, expectedTests) : writesLog && logPath === undefined ? PREPARING : undefined
      if (now === undefined || now === phase) return
      phase = now
      if (usesBand) await quietly(() => setPhase($, now))
    }
    const ticker = started === undefined ? undefined : await quietly(() =>
      $.clock.every(1000, async () => {
        if (followsLog) await readPhase(started)
        if (usesBand) return quietly(() => $.ui.invalidate('ui.render'))
        const now = await quietly(() => $.clock.now())
        if (now !== undefined) await quietly(() => $.ui.status(`${label} · ${stopwatch(now - started)}${plainEstimate(now - started, usual)}${phase ? ` · ${phase}` : ''}`))
      }),
    )

    const result = await next(e)

    ticker?.cancel()
    if (!usesBand) await quietly(() => $.ui.status(undefined))
    const ended = await quietly(() => $.clock.now())
    if (started === undefined || ended === undefined) return result

    const text = result.deny !== undefined ? '' : await fullText($, result.text ?? '')
    // The server's own duration leaves out what ran around the call: a project's pre-build hook, a permission prompt.
    const elapsed = reportedDuration(text) ?? ended - started
    await quietly(() => $.store.set(historyKey(history), [...earlier, elapsed].slice(-HISTORY)))
    const outcome = result.deny !== undefined ? { ok: false } : summarize(name, { isError: result.isError === true, text })
    if (result.deny === undefined) await quietly(() => recordRun($, name, outcome.ok, text))
    const total = testTotal(text)
    if (total !== undefined) await quietly(() => $.store.set(testsKey(history), total))
    const compared = comparison(elapsed, earlier)
    const detail = outcome.detail ? ` · ${outcome.detail}` : ''
    const summary = `${outcome.ok ? '✓' : '✗'} ${name} · ${stopwatch(elapsed)}${compared ? ` ${compared}` : ''}${detail}`
    if (usesBand) {
      await quietly(() => endRun($, { at: ended, elapsed, ok: outcome.ok, detail: outcome.detail, comparison: compared }))
    } else {
      // The band stays up with this same line where it draws; elsewhere a toast carries it.
      await quietly(() => $.ui.toast(summary))
    }
    // Long enough that the person has likely looked away; their notification settings decide how it arrives.
    if (elapsed >= LONG_RUN_MS) await quietly(() => $.ui.notify(summary))
    return result
  })
}
