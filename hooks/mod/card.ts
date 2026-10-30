import { average, stopwatch } from './format'
import { covers, flakyLabel, isWholeScope, type LedgerEntry } from './ledger'

/**
 * The project card: what earlier runs in this folder say about the project, in the context of a conversation's first
 * message. The engine computes that context once per conversation and keeps the answer until a compaction or `/clear`
 * reads it again, so the card is built then, and sent once. It's kept small: every conversation carries it.
 */

/** The context block's name, which the engine renders as its heading. */
export const CARD_BLOCK = 'xcrewProjectCard'
/** How long the conversation's first request waits for the card; a card not built by then stays out. */
export const CARD_WAIT_MS = 1_500
export const CARD_MAX_LINES = 10
export const CARD_MAX_CHARACTERS = 800
/** A full run at least this long is worth a selection instead. */
export const SLOW_FULL_RUN_MS = 2 * 60_000
const DURATIONS_SHOWN = 5
const SELECTIONS_SHOWN = 3
/** The red line's names stop here, so its count of the rest is never cut off. */
const RED_LINE_MAX = 360

/** A run scope's stored history: its durations, and its test total when it's a test run. */
export type ScopeHistory = { scope: string; runs: readonly number[]; tests?: number }

/** The card's text, or nothing when no run has left anything to say. */
export function cardText(history: readonly ScopeHistory[], red: readonly LedgerEntry[], branch: string): string | undefined {
  const timed = history.filter(entry => entry.runs.length > 0).map(entry => ({ ...entry, usual: average(entry.runs) })).sort((a, b) => b.usual - a.usual)
  if (timed.length === 0 && red.length === 0) return undefined
  const durations = timed.slice(0, DURATIONS_SHOWN).map(({ scope, usual, tests }) => `- ${scope}: usually ${stopwatch(usual)}${tests === undefined ? '' : `, ${tests} tests`}`)
  const slow = timed.find(entry => isWholeScope(entry.scope) && entry.tests !== undefined && entry.usual >= SLOW_FULL_RUN_MS)
  const selections = slow ? timed.filter(entry => entry.scope !== slow.scope && covers(slow.scope, entry.scope)) : []
  // The red tests come first: when the card is cut, what's still failing matters more than how long runs take.
  return capped([
    'Xcrew\'s notes on this project, from earlier runs:',
    ...(red.length > 0 ? [redLine(red, branch)] : []),
    ...durations,
    ...(timed.length > DURATIONS_SHOWN ? [`- +${timed.length - DURATIONS_SHOWN} more run scopes`] : []),
    ...(slow && selections.length > 0
      ? [`- A full ${slow.scope} run takes ${stopwatch(slow.usual)}; selections run before: ${selections.slice(0, SELECTIONS_SHOWN).map(entry => entry.scope).join(', ')}${more(selections.length, SELECTIONS_SHOWN)}.`]
      : []),
  ])
}

/** The red tests, as many as fit, then how many more. */
function redLine(red: readonly LedgerEntry[], branch: string): string {
  const opening = `- Still red on ${branch}: `
  const names: string[] = []
  for (const entry of red) {
    const name = `${entry.test}${flakyLabel(entry)} (${entry.failing})`
    if (names.length > 0 && opening.length + [...names, name].join(', ').length + more(red.length, names.length + 1).length > RED_LINE_MAX) break
    names.push(name)
  }
  return `${opening}${names.join(', ')}${more(red.length, names.length)}`
}

function more(count: number, shown: number): string {
  return count > shown ? ` +${count - shown} more` : ''
}

/** At most `CARD_MAX_LINES` lines and `CARD_MAX_CHARACTERS` characters: a line that doesn't fit is cut, and the lines after it dropped. */
function capped(lines: readonly string[]): string {
  const kept: string[] = []
  for (const line of lines.slice(0, CARD_MAX_LINES)) {
    const room = CARD_MAX_CHARACTERS - [...kept, ''].join('\n').length
    if (room <= 1) break
    kept.push(line.length > room ? `${line.slice(0, room - 1)}…` : line)
  }
  return kept.join('\n')
}
