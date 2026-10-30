import { DURATIONS_SHOWN, durationLine, timedScopes, type ScopeHistory } from './card'
import type { LedgerEntry } from './ledger'

/**
 * A pull request's evidence: `xcrew evidence`'s block for this branch, then the images to attach, from the ledger and the
 * run times the mod holds. The CLI reads the result bundles and words it; the mod sends what only it knows.
 */
export const EVIDENCE_TOOL = {
  name: 'evidence',
  description:
    "Xcrew: the evidence this branch's runs give for a pull request: the tests it took from red to green, with their failing run's images, the tests still red, the coverage and warnings of the lines it changed, and the usual run times. " +
    "Ask it before writing a pull request's body. It answers with a `## Evidence` block to put in the body as it is, then the local images, which go to the person to attach only if they agree; their paths never go in the pull request.",
  inputSchema: { type: 'object', properties: {} },
}

/** The full name Claude calls it by: a plugin's registered tool is `mcp__<plugin>__<name>`. */
export const EVIDENCE_TOOL_NAME = 'mcp__xcrew__evidence'

/** What `xcrew evidence` reads on stdin: the branch's ledger, and the run times of the scopes last run in this folder. */
export function evidenceInput(entries: readonly LedgerEntry[], scopes: readonly ScopeHistory[]): string {
  const times = timedScopes(scopes).slice(0, DURATIONS_SHOWN).map(({ scope, usual, tests }) => durationLine(scope, usual, tests))
  return JSON.stringify({ ledger: entries, times })
}
