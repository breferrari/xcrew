import type { BandProblems } from '../../types'
import type { Problem } from './cli'

/**
 * The most serious problem the doctor found, for the band, and how many more; none when it found
 * nothing. The doctor lists them worst first, and reports nothing outside an Apple-platform project.
 */
export function mostSerious(found: Problem[]): BandProblems | null {
  const [first] = found
  return first ? { isFailure: first.status === 'fail', message: first.message, more: found.length - 1 } : null
}
