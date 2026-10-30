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

/** A gauge drawn like a status line's: heavy cells for the part done, light ones for the rest, to half a cell. */
export function gauge(fraction: number, cells: number): { done: string; rest: string } {
  let halves = Math.round(fraction * cells * 2)
  if (fraction > 0 && halves === 0) halves = 1
  halves = Math.min(halves, cells * 2)
  const full = Math.floor(halves / 2)
  const half = halves % 2
  return { done: '━'.repeat(full) + (half ? '╸' : ''), rest: '─'.repeat(cells - full - half) }
}

/** Cells in the gauge: wide enough to move each few seconds, narrow enough to leave room for the rest. */
const GAUGE_CELLS = 8

/** The gauge of the time so far against the usual time, and how much is left; none without a usual time. */
export function estimate(elapsed: number, usual: number | undefined): { done: string; rest: string; text: string; isOver: boolean } | undefined {
  if (usual === undefined || usual <= 0) return undefined
  return { ...gauge(elapsed / usual, GAUGE_CELLS), ...remaining(elapsed, usual) }
}

/** `~0:15 left` while under the usual time (an estimate), `0:08 over` once past it. */
export function remaining(elapsed: number, usual: number): { text: string; isOver: boolean } {
  const left = usual - elapsed
  return left >= 0 ? { text: `~${stopwatch(left)} left`, isOver: false } : { text: `${stopwatch(-left)} over`, isOver: true }
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

/** A time on this Mac's clock with its day, `Oct 30 14:02`: a record that spans days says which. */
export function dayAndTime(at: number): string {
  const date = new Date(at)
  const pad = (value: number) => String(value).padStart(2, '0')
  return `${MONTHS[date.getMonth()]} ${date.getDate()} ${pad(date.getHours())}:${pad(date.getMinutes())}`
}

/** Items one after another: `a`, `a and b`, `a, b and c`. */
export function joined(items: readonly string[]): string {
  return items.length > 1 ? `${items.slice(0, -1).join(', ')} and ${items.at(-1)}` : (items[0] ?? '')
}
