import type { Failure, Head, Repetition } from './cli'
import { dayAndTime } from './format'
import { scopeParts } from './context'
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
export type LedgerEntry = { test: string; red: LedgerRun & { message: string; bundle?: string }; failing: string; green?: LedgerRun; last: number; flaky?: Flakiness; target?: string }

/** A flaky mark: the counts of the repeated run that found the test flaky, and that run's scope and time (absent in a mark kept before they were). */
export type Flakiness = { failed: number; runs: number; scope?: string; at?: number }

export type Ledger = { entries: LedgerEntry[]; updated: number }

/** A finished test run, as the ledger reads it. `ranAll`: it ran every test its scope names, so its passes count. */
export type TestRun = LedgerRun & { ok: boolean; failures: readonly Failure[]; ranAll: boolean; repeated?: readonly Repetition[]; bundle?: string }

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
  return passed === failed || (isWholeScope(passed) && scopeParts(failed).base === passed)
}

/**
 * Whether a run of `passed` scope ran `test`, red in `failing`: the scopes `covers` matches, or the same tool and scheme
 * with a selection that reaches the test. A selection is `TestTarget[/TestClass[/TestMethod]]` (`man xcodebuild`), a
 * Swift Testing method with or without its `()`, and the ledger names a test `Suite/test`. With its `target`, from the
 * result bundle, a selection reaches the test when it names that target and, past it, the test or a class it's in.
 * Without one, as in entries recorded before the report named it, the target comes from the selections of the run it
 * failed in: a selection of a class or method reaches the test under a target that run could have run it in, or under
 * any target when that run selected none; a selection of a whole target only when that run's selections leave the test
 * exactly one target.
 */
export function reaches(passed: string, test: string, failing: string, target?: string): boolean {
  if (covers(passed, failing)) return true
  const pass = scopeParts(passed), fail = scopeParts(failing)
  if (pass.base !== fail.base) return false
  if (target !== undefined) return pass.selections.map(path).some(([named = '', ...rest]) => named === target && within(test, rest))
  // The targets the failing run could have run the test in; none known when it selected none.
  const targets = new Set(fail.selections.map(path).filter(([, ...rest]) => within(test, rest)).map(([target = '']) => target))
  return pass.selections.map(path).some(([target = '', ...rest]) =>
    rest.length > 0
      ? within(test, rest) && (fail.selections.length === 0 || targets.has(target))
      : targets.size === 1 && targets.has(target),
  )
}

/** A selection's components, a Swift Testing method's `()` taken off. */
function path(selection: string): string[] {
  return (selection.endsWith('()') ? selection.slice(0, -2) : selection).split('/')
}

/** Whether `test` (`Suite/test`) is the class or method `components` name, or in it; no components name everything. */
function within(test: string, components: string[]): boolean {
  const named = components.join('/')
  return named === '' || test === named || test.startsWith(`${named}/`)
}

/** Whether a run scope is a tool and scheme's whole suite, not a selection of its tests. */
export function isWholeScope(scope: string): boolean {
  return scopeParts(scope).selections.length === 0
}

/**
 * The ledger after a test run.
 * - A failing test enters red, or turns red again after a green, keeping its first red; either way it now fails in this
 *   run's scope.
 * - A run that ran every test of its scope turns green each red test it reaches and didn't fail, a failing run
 *   included: its other tests passed. A run that didn't get as far as tests (a build failure) turns nothing green.
 * - An entry no run has written for as long as the history is kept is dropped.
 */
export function afterTestRun(ledger: Ledger | undefined, run: TestRun): Ledger {
  const failed = new Map(run.failures.filter(failure => failure.isTest).map(failure => [failure.title, failure]))
  const testsRan = run.ok || failed.size > 0
  // The CLI's verdict on each repeated test. A flaky test stays red, marked so, until a repeated run passes it every
  // time; one run passing it is no evidence. A test failing every run is a real failure, flaky no longer.
  const repeated = new Map((run.repeated ?? []).map(test => [test.test, test]))
  const failing = new Set([...failed.keys(), ...[...repeated.values()].filter(test => test.verdict === 'flaky' || test.verdict === 'real').map(test => test.test)])
  const flakyAfter = (test: string, before?: LedgerEntry['flaky']) => {
    const verdict = repeated.get(test)
    if (verdict?.verdict === 'flaky') return { failed: verdict.failed, runs: verdict.runs, scope: run.scope, at: run.at }
    return verdict?.verdict === 'real' ? undefined : before
  }
  const entries = (ledger?.entries ?? []).filter(entry => !isStale(entry.last, run.at)).map((entry): LedgerEntry => {
    if (failing.has(entry.test)) {
      const flaky = flakyAfter(entry.test, entry.flaky)
      const target = failed.get(entry.test)?.target ?? entry.target
      return { test: entry.test, red: entry.red, failing: run.scope, last: run.at, ...(flaky ? { flaky } : {}), ...(target ? { target } : {}) }
    }
    const cleared = !entry.flaky || repeated.get(entry.test)?.verdict === 'passed'
    const passes = !entry.green && cleared && run.ranAll && testsRan && reaches(run.scope, entry.test, entry.failing, entry.target)
    return passes ? { ...entry, green: { scope: run.scope, at: run.at }, last: run.at } : entry
  })
  for (const test of failing) {
    if (entries.some(entry => entry.test === test)) continue
    const flaky = flakyAfter(test)
    const message = failed.get(test)?.message ?? verdictMessage(repeated.get(test))
    const target = failed.get(test)?.target
    entries.push({ test, red: { scope: run.scope, at: run.at, message: firstLine(message), bundle: run.bundle }, failing: run.scope, last: run.at, ...(flaky ? { flaky } : {}), ...(target ? { target } : {}) })
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

/** The ledger as Claude reads it for a test plan, and the person through `/xcrew ledger`. */
export function ledgerText(ledger: Ledger | undefined, head: Head): string {
  const name = label(head, true)
  const entries = ledger?.entries ?? []
  if (entries.length === 0) return `No test has failed on ${name} yet.`
  const green = entries.filter((entry): entry is GreenEntry => entry.green !== undefined)
  const red = entries.filter(entry => !entry.green)
  const redPart = (entry: LedgerEntry) => `red ${dayAndTime(entry.red.at)} in ${entry.red.scope}: ${entry.red.message}`
  const named = (entry: LedgerEntry) => `${entry.test}${flakyLabel(entry)}`
  return [
    ...(green.length > 0 ? [`Red, then green, on ${name} (${count(green.length)}):`, ...green.map(entry => `- ${named(entry)}: ${redPart(entry)}; green ${dayAndTime(entry.green.at)} in ${entry.green.scope}`)] : []),
    ...(red.length > 0 ? [`Still red (${red.length}):`, ...red.map(entry => `- ${named(entry)}: ${redPart(entry)}`)] : []),
  ].join('\n')
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
  const line = (entry: FlakyEntry) =>
    `- ${entry.test}: ${flakyCounts(entry.flaky)}, in ${entry.flaky.scope ?? entry.failing}${entry.green ? `; passed every run of a repeated run since, in ${entry.green.scope}` : ''}`
  return [`Flaky on ${name} (${count(flaky.length)}):`, ...flaky.map(line)].join('\n')
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

/** ` (flaky: failed 2 of 5 runs)` for a test marked flaky, and nothing otherwise: the ledger and the card say it alike. */
export function flakyLabel(entry: LedgerEntry): string {
  return entry.flaky ? ` (flaky: ${flakyCounts(entry.flaky)})` : ''
}

/** `failed 2 of 5 runs`: how a flaky mark's counts read wherever it's shown. */
function flakyCounts(flaky: Flakiness): string {
  return `failed ${flaky.failed} of ${flaky.runs} runs`
}
