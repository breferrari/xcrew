import type { FullRun } from '../../types'
import { AFFECTED_TOOL } from './affected'
import { stopwatch } from './format'

/**
 * The loop budget: a scope's whole suite run again and again in a short while, each run minutes long, where the tests a
 * change can break would do. Past it, the run's result sends Claude to the affected tests, once; a fast suite never
 * gets there, and the run itself always goes ahead.
 */

/** How many full runs of one scope, within `LOOP_WINDOW_MS`, adding up to `LOOP_TESTING_MS`, cross the budget. */
export const LOOP_RUNS = 3
export const LOOP_WINDOW_MS = 30 * 60_000
export const LOOP_TESTING_MS = 3 * 60_000

/** A scope's full runs once `run` has ended, and whether they crossed the budget; after a crossing the count starts again. */
export function afterFullRun(earlier: readonly FullRun[], run: FullRun): { runs: FullRun[]; crossed?: FullRun[] } {
  const runs = [...earlier.filter(each => run.at - each.at <= LOOP_WINDOW_MS), run]
  const testing = runs.reduce((sum, each) => sum + each.ms, 0)
  return runs.length >= LOOP_RUNS && testing >= LOOP_TESTING_MS ? { runs: [], crossed: runs } : { runs }
}

/** What Claude reads after the run that crossed the budget. Only MobileBuildMCP's tests are selected with `-only-testing:`. */
export function loopNote(scope: string, runs: readonly FullRun[], selectsWithOnlyTesting: boolean): string {
  const first = runs[0]
  const last = runs[runs.length - 1]
  const span = first && last ? Math.round((last.at - (first.at - first.ms)) / 60_000) : 0
  const testing = runs.reduce((sum, each) => sum + each.ms, 0)
  const select = selectsWithOnlyTesting ? 'run those with `-only-testing:`' : 'run only those'
  return (
    `xcrew: that's the ${ordinal(runs.length)} full run of \`${scope}\` in ${span} min, with ${stopwatch(testing)} of testing. ` +
    `Before the next one, ask the \`${AFFECTED_TOOL.name}\` tool which test targets this branch's changes can break, and ${select}. ` +
    'When it says to run the whole suite, run it; and run the whole suite again before the pull request.'
  )
}

/** `3rd`, `4th`, `11th`, `21st`. */
function ordinal(count: number): string {
  const teen = count % 100 >= 11 && count % 100 <= 13
  const suffix = teen ? 'th' : ({ 1: 'st', 2: 'nd', 3: 'rd' } as Record<number, string>)[count % 10] ?? 'th'
  return `${count}${suffix}`
}
