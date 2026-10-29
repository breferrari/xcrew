import type { BandRun, ResultRow } from '../../types'
import type { Failure } from './cli'
import type { ToolKind } from './tools'

/** How many failures a row lists before counting the rest. */
const FAILURES_SHOWN = 3

/** A build or a test run has a row; an app launch keeps its own output, which says where the app is and what it logged. */
export function drawsRow(kind: ToolKind | undefined): boolean {
  return kind === 'build' || kind === 'test'
}

/** None for a failure xcrew couldn't read: the result Claude read says more than a bare ✗. */
export function rowOf(ended: NonNullable<BandRun['ended']>, failures: readonly Failure[]): ResultRow | undefined {
  if (!ended.ok && !ended.detail && failures.length === 0) return undefined
  const listed = ended.hasFailures ? failures : []
  return { ended, failures: listed.slice(0, FAILURES_SHOWN).map(({ message: _, ...shown }) => shown), more: Math.max(0, listed.length - FAILURES_SHOWN) }
}
