/** One awaited step before a build, test or run call reached its server, and how long it took. */
export type Step = { name: string; ms: number }
/** A call that waited at least `SLOW_PRECALL_MS` before it reached its server: its tool, when, and each step. */
export type Timing = { tool: string; at: number; steps: Step[] }

/** Where the timings are kept, across sessions: the next look may come after a restart. */
export const TIMINGS_KEY = 'timings'
/** A wait below this keeps nothing. */
export const SLOW_PRECALL_MS = 1_000
/** How many slow calls are kept, newest last. */
export const TIMINGS_KEPT = 20

/** The kept timings with `added`, a call that waited `SLOW_PRECALL_MS` or more: the newest `TIMINGS_KEPT`. */
export function keptTimings(stored: unknown, added: Timing): Timing[] {
  return [...timingsOf(stored), added].slice(-TIMINGS_KEPT)
}

/**
 * `tool`'s wait before it reached its server, from `from` to `to`, when it came to `SLOW_PRECALL_MS` or more with the
 * stale-build guard's `checked` time before it: the guard's check, the steps timed, each name once, and the rest as
 * `other`. Nothing for a shorter wait, or when either time couldn't be read.
 */
export function waitOf(tool: string, from: number | undefined, to: number | undefined, checked: number | undefined, steps: readonly Step[]): Timing | undefined {
  if (from === undefined || to === undefined || to - from + (checked ?? 0) < SLOW_PRECALL_MS) return undefined
  const timed = steps.reduce((total, step) => total + step.ms, 0)
  const all = [...(checked ? [{ name: 'staleCheck', ms: checked }] : []), ...steps, ...(to - from > timed ? [{ name: 'other', ms: to - from - timed }] : [])]
  const merged = Object.entries(all.reduce<Record<string, number>>((byName, step) => ({ ...byName, [step.name]: (byName[step.name] ?? 0) + step.ms }), {})).map(([name, ms]) => ({ name, ms }))
  return { tool, at: from, steps: merged }
}

/** `/xcrew timings`: each slow call, newest first, with its steps, the slowest first. */
export function timingsText(stored: unknown): string {
  const kept = timingsOf(stored)
  if (kept.length === 0) return 'No build, test or run call has waited a second or more before it started.'
  const lines = [...kept].reverse().map(timing => {
    const steps = [...timing.steps].sort((a, b) => b.ms - a.ms).map(step => `${step.name} ${seconds(step.ms)}`)
    return `- ${timing.tool}, ${new Date(timing.at).toISOString().slice(0, 16).replace('T', ' ')} UTC: ${seconds(waited(timing))} before it started: ${steps.join(', ')}`
  })
  return ['The build, test and run calls that waited a second or more before they started, newest first:', ...lines].join('\n')
}

function waited(timing: Timing): number {
  return timing.steps.reduce((total, step) => total + step.ms, 0)
}

function seconds(ms: number): string {
  return `${(ms / 1000).toFixed(1)} s`
}

/** The kept timings, without any entry that isn't one. */
function timingsOf(stored: unknown): Timing[] {
  if (!Array.isArray(stored)) return []
  return stored.filter((entry): entry is Timing => {
    const timing = entry as Partial<Timing> | null
    return typeof timing?.tool === 'string' && typeof timing.at === 'number' && Array.isArray(timing.steps)
      && timing.steps.every(step => typeof step?.name === 'string' && typeof step.ms === 'number')
  })
}
