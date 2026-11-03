import type { ElsewhereRun, ElsewhereRuns } from '../../types'

/**
 * How long the line keeps what `xcrew runs` last answered when it can't answer: as long as a run's log may go quiet and
 * the run still count as going (`OtherRuns.quietFor`, which a test pairs with this).
 */
export const ELSEWHERE_KEPT_MS = 90_000
/** How often the other worktrees' runs are read again while the line shows or this session's own run goes. */
export const ELSEWHERE_EVERY_MS = 5_000
/** How many runs the line names before it counts the rest. */
const NAMED = 2

/** What the line holds after a read: the CLI's answer as of `now`, or, when it couldn't answer, what it held until that ages out. */
export function afterRead(held: ElsewhereRuns | null, read: ElsewhereRun[] | undefined, now: number): ElsewhereRuns | null {
  if (read !== undefined) return read.length > 0 ? { runs: read, at: now } : null
  return held && now - held.at < ELSEWHERE_KEPT_MS ? held : null
}

/** `elsewhere: feature · test_sim · testing 120 of 959`: a fact, the first runs named and the rest counted. */
export function elsewhereText(runs: ElsewhereRun[]): string {
  const named = runs.slice(0, NAMED).map(run => [run.worktree, run.tool, ...(run.phase ? [run.phase] : [])].join(' · '))
  const more = runs.length > NAMED ? [`+${runs.length - NAMED} more`] : []
  return `elsewhere: ${[...named, ...more].join('; ')}`
}
