import type { Failure, Head } from './cli'
import { dayAndTime } from './format'
import { isStale } from './timing'

/**
 * The red-to-green ledger: for each test on a branch, the run where it first failed and the later run that passed it, as
 * the evidence a pull request's test plan names. It's kept in the store under the project's real root and its branch, or
 * its commit when HEAD is detached, so it outlives a session. What no run has written for as long as the history is
 * kept is dropped: a test's entry, and a branch's whole ledger.
 */

export const LEDGER_PREFIX = 'ledger.'

/** A run in the ledger: its scope (`test_sim · App › AppTests`) and when it ended. */
export type LedgerRun = { scope: string; at: number }

/**
 * One test: its first red, the scope it fails in now (where a pass must run it), its green once seen, and when a run
 * last wrote it.
 */
export type LedgerEntry = { test: string; red: LedgerRun & { message: string }; failing: string; green?: LedgerRun; last: number }

export type Ledger = { entries: LedgerEntry[]; updated: number }

/** A finished test run, as the ledger reads it. `ranAll`: it ran every test its scope names, so its passes count. */
export type TestRun = LedgerRun & { ok: boolean; failures: readonly Failure[]; ranAll: boolean }

/** The checkout as the ledger names it: its branch, or its commit, short in text and whole in the key. */
export function label(head: Head, isShort: boolean): string {
  if (head.branch) return head.branch
  if (head.commit) return `commit ${isShort ? head.commit.slice(0, 12) : head.commit}`
  return isShort ? 'this folder' : ''
}

export function ledgerKey(head: Head): string {
  return `${LEDGER_PREFIX}${head.root} @ ${label(head, false)}`
}

/** A ledger as stored, or none: a value in another shape is ignored rather than trusted. */
export function ledgerOf(stored: unknown): Ledger | undefined {
  const ledger = stored as Ledger | undefined
  return Array.isArray(ledger?.entries) && typeof ledger?.updated === 'number' ? ledger : undefined
}

/**
 * Whether a run of `passed` scope ran the tests a run of `failed` scope did: the same scope, or the whole suite of the
 * same tool and scheme. A pass of another scheme or selection never ran them.
 */
export function covers(passed: string, failed: string): boolean {
  return passed === failed || (isWholeScope(passed) && failed.startsWith(`${passed} › `))
}

/** Whether a run scope is a tool and scheme's whole suite, not a selection of its tests. */
export function isWholeScope(scope: string): boolean {
  return !scope.includes(' › ')
}

/**
 * The ledger after a test run.
 * - A failing test enters red, or turns red again after a green, keeping its first red; either way it now fails in this
 *   run's scope.
 * - A run that ran every test of its scope turns green each red test it covers and didn't fail, a failing run
 *   included: its other tests passed. A run that didn't get as far as tests (a build failure) turns nothing green.
 * - An entry no run has written for as long as the history is kept is dropped.
 */
export function afterTestRun(ledger: Ledger | undefined, run: TestRun): Ledger {
  const failed = new Map(run.failures.filter(failure => failure.isTest).map(failure => [failure.title, failure]))
  const testsRan = run.ok || failed.size > 0
  const entries = (ledger?.entries ?? []).filter(entry => !isStale(entry.last, run.at)).map((entry): LedgerEntry => {
    if (failed.has(entry.test)) return { test: entry.test, red: entry.red, failing: run.scope, last: run.at }
    const passes = !entry.green && run.ranAll && testsRan && covers(run.scope, entry.failing)
    return passes ? { ...entry, green: { scope: run.scope, at: run.at }, last: run.at } : entry
  })
  for (const [test, failure] of failed) {
    if (!entries.some(entry => entry.test === test)) entries.push({ test, red: { scope: run.scope, at: run.at, message: firstLine(failure.message) }, failing: run.scope, last: run.at })
  }
  return { entries, updated: run.at }
}

/** The stored ledgers no run has written for as long as the history is kept. */
export function staleLedgers(stored: Readonly<Record<string, unknown>>, now: number): string[] {
  return Object.entries(stored).filter(([, value]) => isStale(ledgerOf(value)?.updated, now)).map(([key]) => key)
}

type GreenEntry = LedgerEntry & { green: LedgerRun }

/** The ledger as Claude reads it for a test plan, and the person through `/xcrew ledger`. */
export function ledgerText(ledger: Ledger | undefined, head: Head): string {
  const name = label(head, true)
  const entries = ledger?.entries ?? []
  if (entries.length === 0) return `No test has failed on ${name} yet.`
  const green = entries.filter((entry): entry is GreenEntry => entry.green !== undefined)
  const red = entries.filter(entry => !entry.green)
  const redPart = (entry: LedgerEntry) => `red ${dayAndTime(entry.red.at)} in ${entry.red.scope}: ${entry.red.message}`
  return [
    ...(green.length > 0 ? [`Red, then green, on ${name} (${count(green.length)}):`, ...green.map(entry => `- ${entry.test}: ${redPart(entry)}; green ${dayAndTime(entry.green.at)} in ${entry.green.scope}`)] : []),
    ...(red.length > 0 ? [`Still red (${red.length}):`, ...red.map(entry => `- ${entry.test}: ${redPart(entry)}`)] : []),
  ].join('\n')
}

function count(tests: number): string {
  return `${tests} ${tests === 1 ? 'test' : 'tests'}`
}

/** A failure message's first line, cut short: the ledger points at the failure, the pane shows it whole. */
function firstLine(message: string): string {
  const line = message.split('\n')[0] ?? ''
  return line.length > 100 ? `${line.slice(0, 99)}…` : line
}

/** The tool Claude reads the ledger through, behind ToolSearch as an MCP server's tool is, so it costs a session nothing until searched. */
export const LEDGER_TOOL = {
  name: 'ledger',
  description:
    'Xcrew: the tests seen failing and then passing on the checked-out git branch, each with the run where it failed and the run that passed it, and the tests still failing. ' +
    "Markdown for a pull request's test plan. Takes no input.",
}

/** The full name Claude calls it by: a plugin's registered tool is `mcp__<plugin>__<name>`. */
export const LEDGER_TOOL_NAME = 'mcp__xcrew__ledger'

export const LEDGER_UNAVAILABLE = "The ledger couldn't be read: xcrew's CLI didn't say which branch is checked out. Run `/xcrew doctor`."
