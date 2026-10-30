import type { FullRun } from '../../types'
import { AFFECTED_TOOL } from './affected'
import { stopwatch } from './format'

/**
 * The loop budget: a scope's whole suite run again and again in a short while, each run minutes long, where the tests a
 * change can break would do. Past it, the run's result names the `affected` tool, once; a fast suite never gets there,
 * and the run itself always goes ahead.
 */

/** The last `LOOP_RUNS` full runs of one scope, all within `LOOP_WINDOW_MS`, adding up to `LOOP_TESTING_MS`, cross the budget. */
export const LOOP_RUNS = 3
export const LOOP_WINDOW_MS = 30 * 60_000
export const LOOP_TESTING_MS = 3 * 60_000

/** The runs that crossed the budget, with how long they spent testing. */
export type Crossing = { runs: readonly [FullRun, ...FullRun[]]; testing: number }

/** A scope's full runs once `run` has ended, and the crossing when they reach the budget; after one the count starts again. */
export function afterFullRun(earlier: readonly FullRun[], run: FullRun): { runs: FullRun[]; crossed?: Crossing } {
  const recent = [...earlier.filter(each => run.at - each.at <= LOOP_WINDOW_MS), run].slice(-LOOP_RUNS)
  const [first, ...rest] = recent
  const testing = recent.reduce((sum, each) => sum + each.ms, 0)
  if (first === undefined || recent.length < LOOP_RUNS || testing < LOOP_TESTING_MS) return { runs: recent }
  return { runs: [], crossed: { runs: [first, ...rest], testing } }
}

/** What Claude reads after the run that crossed the budget. Only MobileBuildMCP's tests are selected with `-only-testing:`. */
export function loopNote(scope: string, crossed: Crossing, selectsWithOnlyTesting: boolean): string {
  const first = crossed.runs[0]
  const last = crossed.runs[crossed.runs.length - 1] ?? first
  const span = Math.round((last.at - first.at) / 60_000)
  // Only MobileBuildMCP's tests take a selection, through `-only-testing:`; the Xcode MCP's run is the whole suite.
  const tool = `The \`${AFFECTED_TOOL.name}\` tool (search for it)`
  const said = selectsWithOnlyTesting
    ? `${tool} can narrow the next one to the test targets this branch's changes can break, with the \`-only-testing:\` arguments that run them.`
    : `${tool} names the test targets this branch's changes can break.`
  return `xcrew: that's ${crossed.runs.length} full runs of \`${scope}\` in ${span} min, with ${stopwatch(crossed.testing)} of testing. ${said}`
}
