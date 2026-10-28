/** `m:ss`, as a stopwatch reads: 72 000 ms is `1:12`. */
export function stopwatch(ms: number): string {
  const seconds = Math.round(ms / 1000)
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`
}

export function average(values: readonly number[]): number {
  return values.reduce((sum, value) => sum + value, 0) / values.length
}

/** Runs judged slow need this many earlier ones to compare with, and to take this many times as long. */
const SLOW_AFTER_RUNS = 5
const SLOW_RATIO = 1.5

/** How a run compares with the earlier runs of its tool: `(avg 1:10)`, or `(2× its usual 1:50)` when far slower. */
export function comparison(elapsed: number, earlier: readonly number[]): string | undefined {
  if (earlier.length === 0) return undefined
  const usual = average(earlier)
  const ratio = elapsed / usual
  if (earlier.length >= SLOW_AFTER_RUNS && ratio >= SLOW_RATIO) {
    return `(${Number(ratio.toFixed(1))}× its usual ${stopwatch(usual)})`
  }
  return `(avg ${stopwatch(usual)})`
}
