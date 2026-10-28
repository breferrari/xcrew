import { atom, read, update } from 'claude-code'
import type { EngineInterface } from 'claude-code'
import type { BandProblems } from '../../types'

export const problemsState = atom({ plugin: 'xcrew', key: 'problems' } as const, null as BandProblems | null)

/** `FAIL  xcode-mcp/claude-approved  <message>`, as `xcrew doctor` prints a check. */
const LINE = /^(FAIL|warn)\s+\S+\s+(.+)$/

/**
 * Runs `xcrew doctor --problems` and keeps the most serious one for the band. The CLI prints
 * nothing outside an Apple-platform project, so other projects stay quiet.
 */
export async function loadProblems($: EngineInterface): Promise<void> {
  const ran = await $.process.run([`${$.plugin.root}/bin/xcrew`, 'doctor', '--problems'], { timeoutMs: 60_000 })
  const found = ran.stdout
    .split('\n')
    .map(line => LINE.exec(line.trim()))
    .filter(match => match !== null)
    .map(match => ({ isFailure: match[1] === 'FAIL', message: match[2] ?? '' }))
    .sort((a, b) => Number(b.isFailure) - Number(a.isFailure))
  const [first] = found
  if (first) await update($, problemsState, () => ({ ...first, more: found.length - 1 }))
}

/** The band shows problems only until the first run, which then has the band to itself. */
export function clearProblems($: EngineInterface): Promise<unknown> {
  return update($, problemsState, () => null)
}

export function readProblems($: EngineInterface) {
  return read($, problemsState)
}
