import type { Failure } from './cli'
import { isStale } from './command'

/**
 * The red-to-green ledger: for each test on a branch, the run where it first failed and the later run that passed it, as
 * the evidence a pull request's test plan names. It's kept in the store under the project's real root and its branch, or
 * its commit when HEAD is detached, so it outlives a session; a branch's ledger no run has written for as long as the
 * history is kept is dropped.
 */

export const LEDGER_PREFIX = 'ledger.'

/** A run in the ledger: its scope (`test_sim · App › AppTests`) and when it ended. */
export type LedgerRun = { scope: string; at: number }

export type LedgerEntry = { test: string; red: LedgerRun & { message: string }; green?: LedgerRun }

export type Ledger = { entries: LedgerEntry[]; updated: number }

/** Where a checkout stands, as `xcrew project --branch` answers. */
export type Head = { root: string; branch?: string; commit?: string }

/** What `xcrew project --branch` answered, when it named a root. */
export function headOf(answer: unknown): Head | undefined {
  const { root, branch, commit } = (answer ?? {}) as Record<string, unknown>
  if (typeof root !== 'string' || root === '') return undefined
  return { root, ...(typeof branch === 'string' ? { branch } : {}), ...(typeof commit === 'string' ? { commit } : {}) }
}

/** The checkout's name in the ledger's words: its branch, its commit, or nothing outside git. */
export function headName(head: Head): string {
  return head.branch ?? (head.commit ? `commit ${head.commit.slice(0, 12)}` : 'this folder')
}

export function ledgerKey(head: Head): string {
  return `${LEDGER_PREFIX}${head.root} @ ${head.branch ?? (head.commit ? `commit ${head.commit}` : '')}`
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
  return passed === failed || (!passed.includes(' › ') && failed.startsWith(`${passed} › `))
}

/**
 * The ledger after a test run. A failing test enters red, or turns red again after a green, keeping its first red; a
 * passing run turns green each red test it covers. A compile error never enters: no later run passes it.
 */
export function afterTestRun(ledger: Ledger | undefined, run: LedgerRun & { ok: boolean; failures: readonly Failure[] }): Ledger {
  const entries = [...(ledger?.entries ?? [])]
  if (run.ok) {
    for (const [index, entry] of entries.entries()) {
      if (!entry.green && covers(run.scope, entry.red.scope)) entries[index] = { ...entry, green: { scope: run.scope, at: run.at } }
    }
  } else {
    for (const failure of run.failures.filter(failure => failure.isTest)) {
      const index = entries.findIndex(entry => entry.test === failure.title)
      const earlier = entries[index]
      if (!earlier) entries.push({ test: failure.title, red: { scope: run.scope, at: run.at, message: firstLine(failure.message) } })
      else if (earlier.green) entries[index] = { test: earlier.test, red: earlier.red }
    }
  }
  return { entries, updated: run.at }
}

/** The stored ledgers no run has written for as long as the history is kept. */
export function staleLedgers(stored: Readonly<Record<string, unknown>>, now: number): string[] {
  return Object.entries(stored).filter(([, value]) => isStale(ledgerOf(value)?.updated, now)).map(([key]) => key)
}

/** The ledger as Claude reads it for a test plan, and the person through `/xcrew ledger`. */
export function ledgerText(ledger: Ledger | undefined, head: Head): string {
  const name = headName(head)
  const entries = ledger?.entries ?? []
  if (entries.length === 0) return `No test has failed on ${name} yet.`
  const green = entries.filter(entry => entry.green)
  const red = entries.filter(entry => !entry.green)
  const redPart = (entry: LedgerEntry) => `red ${when(entry.red.at)} in ${entry.red.scope}: ${entry.red.message}`
  return [
    ...(green.length > 0 ? [`Red, then green, on ${name} (${count(green.length)}):`, ...green.map(entry => `- ${entry.test}: ${redPart(entry)}; green ${when(entry.green?.at ?? 0)} in ${entry.green?.scope ?? ''}`)] : []),
    ...(red.length > 0 ? [`Still red (${red.length}):`, ...red.map(entry => `- ${entry.test}: ${redPart(entry)}`)] : []),
  ].join('\n')
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

/** A time on this Mac's clock, with its day: a branch's runs can span days. */
function when(at: number): string {
  const date = new Date(at)
  const pad = (value: number) => String(value).padStart(2, '0')
  return `${MONTHS[date.getMonth()]} ${date.getDate()} ${pad(date.getHours())}:${pad(date.getMinutes())}`
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
