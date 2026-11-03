import { ASKED_MS } from './cli'
import type { LedgerEntry } from './ledger'

/**
 * A pull request's evidence: `xcrew evidence`'s block for this branch, then the images to attach, from the ledger the mod
 * holds. The CLI reads the result bundles and words it; the mod sends what only it knows.
 */
export const EVIDENCE_TOOL = {
  name: 'evidence',
  description:
    "Xcrew: the evidence this branch's runs give for a pull request: the tests it took from red to green, with their failing run's images, the tests still red, and the coverage and warnings of the lines it changed. " +
    "It answers with a `## Evidence` block, for the person to add to a pull request's body if they want it, as it is, then the local images, attached only if the person agrees; their paths never go in the pull request.",
  inputSchema: { type: 'object', properties: {} },
}

/** The full name Claude calls it by: a plugin's registered tool is `mcp__<plugin>__<name>`. */
export const EVIDENCE_TOOL_NAME = 'mcp__xcrew__evidence'

/** Asked for, as a `/xcrew` command is: `ASKED_MS`, which the CLI passes down to every bundle and coverage read. */
export const EVIDENCE_TIMEOUT_MS = ASKED_MS

/** Without the branch, its ledger can't be read: said so, rather than evidence that would say no test failed. */
export const EVIDENCE_UNAVAILABLE = "The evidence couldn't be read: xcrew's CLI didn't say which branch is checked out, so the tests it took from red to green aren't known. Run `/xcrew doctor`."

/** What `xcrew evidence` reads on stdin: the branch's ledger. */
export function evidenceInput(entries: readonly LedgerEntry[]): string {
  return JSON.stringify({ ledger: entries })
}
