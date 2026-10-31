import { scopeParts } from './context'

/** How far above the highest count Claude has read for a scheme a new count must be, as a share of it, to be given again. */
export const CONCURRENCY_RISE = 0.25

/** The scheme a run's scope names, without its tool and selections: `App` for `test_sim · App › AppTests/One`. */
export function schemeOfScope(scope: string): string {
  const base = scopeParts(scope).base
  const at = base.indexOf(' · ')
  return at < 0 ? '' : base.slice(at + 3)
}

/** Whether a build's concurrency count is given: the first for its scheme this session, or one at least a quarter above the
 * highest given. A lower count, as an incremental build's log holds, is the log's and not the code's, so it never is. */
export function givesConcurrency(highest: number | undefined, count: number): boolean {
  return highest === undefined || count >= highest * (1 + CONCURRENCY_RISE)
}
