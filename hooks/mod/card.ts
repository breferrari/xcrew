import { average, stopwatch } from './format'
import type { LedgerEntry } from './ledger'

/**
 * The project card: what earlier sessions' runs say about this project, put in Claude's system prompt once a session
 * starts. It sits after the prompt cache's boundary, so it's built once and sent unchanged all session, and it's kept
 * small: every session's prompt carries it.
 */

export const CARD_SECTION = 'xcrew:project-card'
export const CARD_MAX_LINES = 10
export const CARD_MAX_CHARACTERS = 800
/** A full run at least this long is worth a selection instead. */
export const SLOW_FULL_RUN_MS = 2 * 60_000
const DURATIONS_SHOWN = 5
const REDS_SHOWN = 3
const SELECTIONS_SHOWN = 3

/** A run scope's stored history: its durations, and its test total when it's a test run. */
export type ScopeHistory = { scope: string; runs: readonly number[]; tests?: number }

/** The card's text, or nothing when no run has left anything to say. */
export function cardText(history: readonly ScopeHistory[], red: readonly LedgerEntry[], branch: string): string | undefined {
  const timed = history.filter(entry => entry.runs.length > 0).map(entry => ({ ...entry, usual: average(entry.runs) })).sort((a, b) => b.usual - a.usual)
  const durations = timed.slice(0, DURATIONS_SHOWN).map(({ scope, usual, tests }) => `- ${scope}: usually ${stopwatch(usual)}${tests === undefined ? '' : `, ${tests} tests`}`)
  const reds = red.length === 0 ? [] : [`- Still red on ${branch}: ${red.slice(0, REDS_SHOWN).map(entry => `${entry.test} (${entry.failing})`).join(', ')}${more(red.length, REDS_SHOWN)}`]
  const slow = timed.find(entry => !entry.scope.includes(' › ') && entry.tests !== undefined && entry.usual >= SLOW_FULL_RUN_MS)
  const selections = slow ? timed.filter(entry => entry.scope.startsWith(`${slow.scope} › `)) : []
  const hint = slow && selections.length > 0
    ? [`- A full ${slow.scope} run takes ${stopwatch(slow.usual)}; selections run before: ${selections.slice(0, SELECTIONS_SHOWN).map(entry => entry.scope).join(', ')}${more(selections.length, SELECTIONS_SHOWN)}.`]
    : []
  if (durations.length === 0 && reds.length === 0) return undefined
  // The red tests come first: when the card is cut, what's still failing matters more than how long runs take.
  return capped(['Xcrew\'s notes on this project, from earlier runs:', ...reds, ...durations, ...hint])
}

function more(count: number, shown: number): string {
  return count > shown ? ` +${count - shown} more` : ''
}

/** At most `CARD_MAX_LINES` lines and `CARD_MAX_CHARACTERS` characters: a line that doesn't fit is cut, and the lines after it dropped. */
function capped(lines: readonly string[]): string {
  const kept: string[] = []
  let length = 0
  for (const line of lines.slice(0, CARD_MAX_LINES)) {
    const room = CARD_MAX_CHARACTERS - length - (kept.length > 0 ? 1 : 0)
    if (room <= 1) break
    kept.push(line.length > room ? `${line.slice(0, room - 1)}…` : line)
    length += (kept.length > 1 ? 1 : 0) + (kept.at(-1)?.length ?? 0)
  }
  return kept.join('\n')
}
