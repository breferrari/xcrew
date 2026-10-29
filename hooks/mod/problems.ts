import type { BandProblems } from '../../types'
import type { Problem } from './cli'

/**
 * The most serious problem the doctor found, for the band, and how many more; none when it found
 * nothing. The doctor lists them worst first, and reports nothing outside an Apple-platform project.
 */
export function mostSerious(found: Problem[]): BandProblems | null {
  const first = found.find(asksForRestart) ?? found[0]
  if (!first) return null
  return { isFailure: first.status === 'fail', message: first.message, more: found.length - 1, ...(asksForRestart(first) ? { isRestart: true } : {}) }
}

/** The doctor's check that MobileBuildMCP has the current config (`ConfigLoadedCheck`; ManifestTests pairs them). */
export const RESTART_CHECK = 'mobilebuildmcp/config-loaded'

/** A restart is the one step left, and fixes most of what else shows, so it comes first and stays until done. */
function asksForRestart(problem: Problem): boolean {
  return problem.id === RESTART_CHECK
}

/** A warning shows on the band this long after it's first found; it asks for nothing urgent. */
export const WARNING_FOR_MS = 2 * 60_000
/** The doctor runs again after a prompt at most this often. */
export const REREAD_EVERY_MS = 30_000

/** When each problem was first found: the times already known, and `now` for the new ones. */
export function noticed(found: Problem[], seenAt: Readonly<Record<string, number>>, now: number): Record<string, number> {
  return Object.fromEntries(found.map(problem => [problem.id, seenAt[problem.id] ?? now]))
}

/** What the band shows: every failure and a pending restart until done, and each other warning for its first few minutes. */
export function visible(found: Problem[], seenAt: Readonly<Record<string, number>>, now: number): Problem[] {
  return found.filter(problem => problem.status === 'fail' || asksForRestart(problem) || now - (seenAt[problem.id] ?? now) < WARNING_FOR_MS)
}
