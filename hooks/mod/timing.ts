import type { EngineInterface, On } from 'claude-code'
import { comparison, stopwatch } from './format'
import { endRun, startRun } from './band'
import { describe, observe } from './context'
import { summarize } from './results'
import { kindOf, parseTool } from './tools'

/** How many earlier runs of each tool the average covers. */
const HISTORY = 10
export const DURATIONS_PREFIX = 'durations.'
const historyKey = (tool: string) => `${DURATIONS_PREFIX}${tool}`
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

    const started = await quietly(() => $.clock.now())
    // The band draws in colour where a surface can show it; elsewhere the plain status line carries the run.
    const surfaces = (await quietly(() => $.session.surfaces())) ?? []
    const usesBand = surfaces.some(surface => surface === 'terminal' || surface === 'desktop')
    if (usesBand && started !== undefined) await quietly(() => startRun($, { tool: name, target, startedAt: started }))
    const ticker = started === undefined ? undefined : await quietly(() =>
      $.clock.every(1000, async () => {
        if (usesBand) return quietly(() => $.ui.invalidate('ui.render'))
        const now = await quietly(() => $.clock.now())
        if (now !== undefined) await quietly(() => $.ui.status(`${label} · ${stopwatch(now - started)}`))
      }),
    )

    const result = await next(e)

    ticker?.cancel()
    if (!usesBand) await quietly(() => $.ui.status(undefined))
    const ended = await quietly(() => $.clock.now())
    if (started === undefined || ended === undefined) return result

    const elapsed = ended - started
    const earlier = ((await quietly(() => $.store.get(historyKey(name)))) as number[] | undefined) ?? []
    await quietly(() => $.store.set(historyKey(name), [...earlier, elapsed].slice(-HISTORY)))
    const outcome =
      result.deny !== undefined ? { ok: false } : summarize(name, { isError: result.isError === true, text: await fullText($, result.text ?? '') })
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
