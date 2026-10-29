import { atom, read, update } from 'claude-code'
import type { EngineInterface } from 'claude-code'
import type { BandProblems } from '../../types'
import { problems } from './cli'

const problemsState = atom({ plugin: 'xcrew', key: 'problems' } as const, null as BandProblems | null)

/**
 * Asks the doctor what's wrong and keeps the most serious problem for the band. The doctor reports
 * nothing outside an Apple-platform project, so other projects stay quiet.
 */
export async function loadProblems($: EngineInterface): Promise<void> {
  // The doctor lists them worst first.
  const found = await problems($)
  const [first] = found
  if (first) await update($, problemsState, () => ({ isFailure: first.status === 'fail', message: first.message, more: found.length - 1 }))
}

/** The band shows problems only until the first run, which then has the band to itself. */
export function clearProblems($: EngineInterface): Promise<unknown> {
  return update($, problemsState, () => null)
}

export function readProblems($: EngineInterface) {
  return read($, problemsState)
}
