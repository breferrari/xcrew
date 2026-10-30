import { durationLines, type ScopeHistory } from './card'
import type { LedgerEntry } from './ledger'

/**
 * A pull request's evidence: `xcrew evidence`'s block for this branch, then the images to attach, from the ledger and the
 * run times the mod holds. The CLI reads the result bundles and words it; the mod sends what only it knows.
 */
export const EVIDENCE_TOOL = {
  name: 'evidence',
  description:
    "Xcrew: the evidence this branch's runs give for a pull request: the tests it took from red to green, with their failing run's images, the tests still red, the coverage and warnings of the lines it changed, and the usual run times. " +
    "It answers with a `## Evidence` block, for the person to add to a pull request's body if they want it, as it is, then the local images, attached only if the person agrees; their paths never go in the pull request.",
  inputSchema: { type: 'object', properties: {} },
}

/** The full name Claude calls it by: a plugin's registered tool is `mcp__<plugin>__<name>`. */
export const EVIDENCE_TOOL_NAME = 'mcp__xcrew__evidence'

/** Up to ten result bundles' attachments, read a few at a time, and a coverage archive: more than a quick command's time. */
export const EVIDENCE_TIMEOUT_MS = 300_000

/** Without the branch, its ledger can't be read: said so, rather than evidence that would say no test failed. */
export const EVIDENCE_UNAVAILABLE = "The evidence couldn't be read: xcrew's CLI didn't say which branch is checked out, so the tests it took from red to green aren't known. Run `/xcrew doctor`."

/** What `xcrew evidence` reads on stdin: the branch's ledger, and the run times of the scopes last run in this folder. */
export function evidenceInput(entries: readonly LedgerEntry[], scopes: readonly ScopeHistory[]): string {
  return JSON.stringify({ ledger: entries, times: durationLines(scopes) })
}
