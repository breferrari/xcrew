import type { Failure, FlakyMark, Head, Passed, Repetition } from './cli'
import { dayAndTime } from './format'
import { schemeOfScope, scopeParts } from './context'
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
 * One test: its first red, the scope it fails in now (where a pass must run it), its green once seen, when a run last
 * wrote it, and its target, from the result bundle, when the report named one.
 */
export type LedgerEntry = { test: string; red: LedgerRun & { message: string; bundle?: string }; failing: string; green?: LedgerRun & { listed?: true }; last: number; flaky?: Flakiness; target?: string; unseen?: LedgerRun }

/**
 * A flaky mark: the failures and runs of the repeated runs up to its last failure, and the repeated run that found the
 * test flaky, its scope and time (absent in a mark kept before they were). With the CLI's answer, the passes in a row
 * since, the passes needed and whether it has them; absent in a mark kept before, or when the CLI couldn't answer.
 */
export type Flakiness = { failed: number; runs: number; scope?: string; at?: number; passes?: number; needed?: number; settled?: boolean }

export type Ledger = { entries: LedgerEntry[]; updated: number }

/**
 * A finished test run, as the ledger reads it. `passed`: the tests its results list as passed, each with the test bundle
 * the result bundle files it under when it names one; absent when the CLI couldn't read them. `narrowed`: the run left some
 * of its scope's tests out on purpose, by a skip, a test plan or a configuration, or repeated them.
 */
export type TestRun = LedgerRun & { ok: boolean; failures: readonly Failure[]; repeated?: readonly Repetition[]; passed?: readonly Passed[]; bundle?: string; narrowed?: true }

/** The checkout as the ledger names it: its branch, or its commit, short in text and whole in the key. */
export function label(head: Head, isShort: boolean): string {
  if (head.branch) return head.branch
  if (head.commit) return `commit ${isShort ? head.commit.slice(0, 12) : head.commit}`
  return isShort ? 'this folder' : ''
}

export function ledgerKey(head: Head): string {
  return `${LEDGER_PREFIX}${head.root} @ ${label(head, false)}`
}

/** The checkout a stored ledger's key names: up to its last ` @ `, as the label after it, a branch's name or `commit <sha>`, holds no ` @ `. */
export function ledgerRoot(key: string): string | undefined {
  if (!key.startsWith(LEDGER_PREFIX)) return undefined
  const at = key.lastIndexOf(' @ ')
  return at < 0 ? undefined : key.slice(LEDGER_PREFIX.length, at)
}

/** A ledger as stored, or none: a value in another shape is ignored rather than trusted. A green
 * not marked `listed` was inferred from a run's selection by an older xcrew, and could name a test that run never
 * ran; its red is long over, so the entry is left out, and the ledger rebuilds from new runs. One marked flaky keeps its
 * mark and its red, without the green: one clean repeated run turned it green then, short of the passes it needs. An
 * entry that isn't an object is left out too.
 */
export function ledgerOf(stored: unknown): Ledger | undefined {
  const ledger = stored as Ledger | undefined
  if (!Array.isArray(ledger?.entries) || typeof ledger?.updated !== 'number') return undefined
  const entries = ledger.entries.filter((entry): entry is LedgerEntry => typeof entry === 'object' && entry !== null)
  return { ...ledger, entries: entries.flatMap(entry => (!entry.green || entry.green.listed ? [entry] : entry.flaky ? [withoutGreen(entry)] : [])) }
}

function withoutGreen({ green: _, ...entry }: LedgerEntry): LedgerEntry {
  return entry
}

/**
 * Whether a run of `passed` scope ran the tests a run of `failed` scope did: the same scope, or the whole suite of the
 * same tool and scheme. A pass of another scheme or selection never ran them.
 */
export function covers(passed: string, failed: string): boolean {
  return passed === failed || (isWholeScope(passed) && scopeParts(failed).base === passed)
}

/**
 * Whether a run of `scope` passed `entry`'s test: its results list the test as passed, under the same scheme as the run
 * it fails in now, whichever tool ran it, and in the target the report named for it when both name one. A Swift Testing name is
 * the same test with its `()` or without. A selection that would reach the test is no evidence: the test may be gone.
 */
export function passes(scope: string, passed: readonly Passed[], entry: LedgerEntry): boolean {
  if (schemeOfScope(scope) !== schemeOfScope(entry.failing)) return false
  const test = bare(entry.test)
  return passed.some(each => bare(each.test) === test && (each.target === undefined || entry.target === undefined || each.target === entry.target))
}

/** Whether a run of `scope` would have run a red of `failing`'s: the same scheme, and its whole suite, or a selection holding each of the red run's own. */
export function wouldRun(scope: string, failing: string): boolean {
  if (schemeOfScope(scope) === '' || schemeOfScope(scope) !== schemeOfScope(failing)) return false
  if (isWholeScope(scope)) return true
  const selected = new Set(scopeParts(scope).selections)
  const reds = scopeParts(failing).selections
  return reds.length > 0 && reds.every(selection => selected.has(selection))
}

/** A test's name without a Swift Testing method's `()`. */
function bare(test: string): string {
  return test.endsWith('()') ? test.slice(0, -2) : test
}

/** Whether a run scope is a tool and scheme's whole suite, not a selection of its tests. */
export function isWholeScope(scope: string): boolean {
  return scopeParts(scope).selections.length === 0
}

/**
 * The ledger after a test run.
 * - A failing test enters red, or turns red again after a green, keeping its first red's date and bundle; either way it
 *   now fails in this run's scope, with this run's message.
 * - A flaky test that fails with no repeated verdict for it, as in a plain run, starts its passes in a row over.
 * - A repeated test takes the CLI's verdict and marks: a flaky one stays red, marked so, until the CLI says its passes in
 *   a row are enough, as one run passing it is no evidence; one failing every run is a real failure, flaky no longer.
 * - A run turns green each red test its results list as passed (`passes`), a failing run included. A run whose
 *   results the CLI couldn't read turns nothing green.
 * - An entry no run has written for as long as the history is kept is dropped.
 */
export function afterTestRun(ledger: Ledger | undefined, run: TestRun, marks?: readonly FlakyMark[]): Ledger {
  const failed = new Map(run.failures.filter(failure => failure.isTest).map(failure => [failure.title, failure]))
  const repeated = new Map((run.repeated ?? []).map(test => [test.test, test]))
  const marked = new Map((marks ?? []).map(mark => [mark.test, mark]))
  const failing = new Set([...failed.keys(), ...[...repeated.values()].filter(test => test.verdict === 'flaky' || test.verdict === 'real').map(test => test.test)])
  const flakyAfter = (test: string, before?: Flakiness): Flakiness | undefined => {
    const verdict = repeated.get(test)?.verdict
    if (verdict === 'real') return undefined
    const mark = marked.get(test)
    const counts = mark ? { failed: mark.failed, runs: mark.runs, passes: mark.passes, needed: mark.needed, settled: mark.settled } : undefined
    if (verdict === 'flaky') return { ...(counts ?? { failed: repeated.get(test)?.failed ?? 0, runs: repeated.get(test)?.runs ?? 0 }), scope: run.scope, at: run.at }
    const after = before && counts ? { ...before, ...counts } : before
    // A failure no repeated verdict counts, a plain run's, adds nothing to the rate but ends the passes in a row.
    return after && verdict === undefined && failed.has(test) ? { ...after, passes: 0, settled: false } : after
  }
  const entries = (ledger?.entries ?? []).filter(entry => !isStale(entry.last, run.at)).map((entry): LedgerEntry => {
    if (failing.has(entry.test)) {
      const flaky = flakyAfter(entry.test, entry.flaky)
      const target = failed.get(entry.test)?.target ?? entry.target
      // Its first red's date and bundle stay, for the evidence block; its message is the newest failure's.
      const message = failed.get(entry.test)?.message ?? verdictMessage(repeated.get(entry.test))
      return { test: entry.test, red: { ...entry.red, message }, failing: run.scope, last: run.at, ...(flaky ? { flaky } : {}), ...(target ? { target } : {}) }
    }
    const flaky = flakyAfter(entry.test, entry.flaky)
    const updated = flaky === entry.flaky ? entry : { ...entry, ...(flaky ? { flaky } : {}), last: run.at }
    const cleared = !flaky || (repeated.get(entry.test)?.verdict === 'passed' && flaky.settled === true)
    const read = !entry.green && run.passed !== undefined
    const listed = read && passes(run.scope, run.passed ?? [], entry)
    if (listed && cleared) {
      const { unseen: _, ...green } = updated
      return { ...green, green: { scope: run.scope, at: run.at, listed: true }, last: run.at }
    }
    // A run that ran it, listing it passed or repeating it, ends a note that one didn't.
    const ranIt = listed || repeated.has(entry.test)
    if (ranIt && updated.unseen) {
      const { unseen: _, ...ran } = updated
      return ran
    }
    // A run whose passed tests are listed whole, from its result bundle, that didn't list it, of its scheme's whole suite or
    // of a selection holding the red's own, as for a test deleted since: said, and the entry's age left as it was, so it
    // goes once no run has failed it for as long as the history is kept. The Xcode MCP's list stops at 100 results, and a
    // run that passed nothing, as a failed build, lists none.
    const listsWhole = run.bundle !== undefined && (run.passed?.length ?? 0) > 0
    const isUnseen = read && !ranIt && listsWhole && !run.narrowed && wouldRun(run.scope, entry.failing)
    return isUnseen ? { ...updated, unseen: { scope: run.scope, at: run.at } } : updated
  })
  for (const test of failing) {
    if (entries.some(entry => entry.test === test)) continue
    const flaky = flakyAfter(test)
    const message = failed.get(test)?.message ?? verdictMessage(repeated.get(test))
    const target = failed.get(test)?.target
    entries.push({ test, red: { scope: run.scope, at: run.at, message, bundle: run.bundle }, failing: run.scope, last: run.at, ...(flaky ? { flaky } : {}), ...(target ? { target } : {}) })
  }
  return { entries, updated: run.at }
}

/**
 * A repeated test's red, when no failure of its own was listed: a real one in the CLI's words for its verdict
 * (`ResultBundle.repetitionsNote`); a flaky one's counts are its label's, which each run updates.
 */
function verdictMessage(verdict: Repetition | undefined): string {
  return verdict?.verdict === 'real' ? 'failed every run, a real failure' : 'failed some of its repeated runs'
}

/** The stored ledgers no run has written for as long as the history is kept. */
export function staleLedgers(stored: Readonly<Record<string, unknown>>, now: number): string[] {
  return Object.entries(stored).filter(([, value]) => isStale(ledgerOf(value)?.updated, now)).map(([key]) => key)
}

type GreenEntry = LedgerEntry & { green: LedgerRun }
type FlakyEntry = LedgerEntry & { flaky: Flakiness }

/**
 * The ledger as Claude reads it for a test plan, and the person through `/xcrew ledger`. Tests whose runs share a scope
 * are listed under it, named once, as a run of many suites turns many tests red and green together. A test alone in its
 * scopes is one line.
 */
export function ledgerText(ledger: Ledger | undefined, head: Head): string {
  const name = label(head, true)
  const entries = ledger?.entries ?? []
  if (entries.length === 0) return `No test has failed on ${name} yet.`
  const green = entries.filter((entry): entry is GreenEntry => entry.green !== undefined)
  const red = entries.filter(entry => !entry.green)
  const unseen = (entry: LedgerEntry) => (entry.unseen ? `; ${NOT_IN_NEWEST}, ${dayAndTime(entry.unseen.at)}` : '')
  const redPart = (entry: LedgerEntry, scope: string) => `red ${dayAndTime(entry.red.at)}${scope}: ${shownMessage(entry.red.message)}${unseen(entry)}`
  const named = (entry: LedgerEntry) => `${entry.test}${flakyLabel(entry)}`
  const greenLine = (entry: GreenEntry, alone: boolean) =>
    `${named(entry)}: ${redPart(entry, alone ? ` in ${entry.red.scope}` : '')}; green ${dayAndTime(entry.green.at)}${alone ? ` in ${entry.green.scope}` : ''}`
  const greenHead = (entry: GreenEntry, tests: number) =>
    entry.red.scope === entry.green.scope ? `${count(tests)} red, then green, in ${entry.red.scope}:` : `${count(tests)} red in ${entry.red.scope}, then green in ${entry.green.scope}:`
  return [
    ...(green.length > 0 ? [`Red, then green, on ${name} (${count(green.length)}):`, ...grouped(green, entry => JSON.stringify([entry.red.scope, entry.green.scope]), greenLine, greenHead)] : []),
    ...(red.length > 0 ? [`Still red (${red.length}):`, ...grouped(red, entry => entry.red.scope, (entry, alone) => `${named(entry)}: ${redPart(entry, alone ? ` in ${entry.red.scope}` : '')}`, (entry, tests) => `${count(tests)} red in ${entry.red.scope}:`)] : []),
  ].join('\n')
}

/**
 * `entries` as lines, those sharing a `key` together where the first of them stood: one alone as `- <line>`, with its
 * scopes; several under `- <head>`, which names their scopes once, each as `  - <line>` without them.
 */
function grouped<Entry>(entries: Entry[], key: (entry: Entry) => string, line: (entry: Entry, alone: boolean) => string, head: (first: Entry, tests: number) => string): string[] {
  const groups = new Map<string, Entry[]>()
  for (const entry of entries) {
    const shared = key(entry)
    groups.set(shared, [...(groups.get(shared) ?? []), entry])
  }
  return [...groups.values()].flatMap(group => {
    const first = group[0]!
    return group.length === 1 ? [`- ${line(first, true)}`] : [`- ${head(first, group.length)}`, ...group.map(entry => `  - ${line(entry, false)}`)]
  })
}

/**
 * The tests the ledger marks flaky, as `/xcrew flaky` shows them: the one found flaky last first, each with its counts and
 * the repeated run that found it, and the repeated run that has since passed it every time, when one has.
 */
export function flakyText(ledger: Ledger | undefined, head: Head): string {
  const name = label(head, true)
  const foundAt = (entry: FlakyEntry) => entry.flaky.at ?? entry.last
  const flaky = (ledger?.entries ?? []).filter((entry): entry is FlakyEntry => entry.flaky !== undefined).sort((a, b) => foundAt(b) - foundAt(a))
  if (flaky.length === 0) return `No test is marked flaky on ${name}.`
  const since = (entry: FlakyEntry) => {
    if (entry.flaky.needed === undefined) return entry.green ? `; passed every run of a repeated run since, in ${entry.green.scope}` : ''
    return `; ${passedSince(entry.flaky)}${entry.green ? `, the last in ${entry.green.scope}` : ''}`
  }
  const line = (entry: FlakyEntry) => `- ${entry.test}: ${flakyCounts(entry.flaky)}, in ${entry.flaky.scope ?? entry.failing}${since(entry)}`
  const caveat = flaky.some(entry => entry.flaky.needed !== undefined) ? [PASSES_NEEDED] : []
  return [`Flaky on ${name} (${count(flaky.length)}):`, ...flaky.map(line), ...caveat].join('\n')
}

function count(tests: number): string {
  return `${tests} ${tests === 1 ? 'test' : 'tests'}`
}

/**
 * A failure message as the ledger and the evidence show it: its first line, cut short, pointing at the failure, which
 * the store keeps whole and the pane shows whole.
 */
export function shownMessage(message: string): string {
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

/**
 * ` (flaky: failed 2 of 5 runs; passed 5 of the 6 needed in repeated runs since)` for a test marked flaky, without
 * the passes when the CLI hasn't counted them, and nothing otherwise: the ledger and the card say it alike.
 */
export function flakyLabel(entry: LedgerEntry): string {
  if (!entry.flaky) return ''
  return ` (flaky: ${flakyCounts(entry.flaky)}${entry.flaky.needed === undefined ? '' : `; ${passedSince(entry.flaky)}`})`
}

/** What a red test the newest run in its scope didn't run is said to be; the evidence block says it in the same words. */
export const NOT_IN_NEWEST = 'not in the newest run of its scope'

/** Where a mark's passes come from: only a repeated run's count. The evidence block says it in the same words. */
export const PASSES_COUNTED = 'in repeated runs since'

/** What the passes needed are, said once where they're listed. */
export const PASSES_NEEDED = 'Passes needed: enough in a row that a test failing at the rate it was seen failing would pass them all under 5% of the time. From few runs, that rate can understate a rarer flake.'

/**
 * `passed 5 of the 6 needed in repeated runs since`, or once it has them, `passed 10 in a row in repeated runs since, of 6
 * needed`.
 */
function passedSince(flaky: Flakiness): string {
  const passes = flaky.passes ?? 0
  return flaky.settled ? `passed ${passes} in a row ${PASSES_COUNTED}, of ${flaky.needed} needed` : `passed ${passes} of the ${flaky.needed} needed ${PASSES_COUNTED}`
}

/** `failed 2 of 5 runs`: how a flaky mark's counts read wherever it's shown. */
function flakyCounts(flaky: Flakiness): string {
  return `failed ${flaky.failed} of ${flaky.runs} runs`
}
