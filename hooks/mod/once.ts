import type { Report } from './cli'
import { givesConcurrency, schemeOfScope } from './concurrency'

/**
 * Adds the run's concurrency note the first time its scheme has one this session, and when its count rises far enough
 * above the highest `given`, the highest count Claude has read by scheme, which it updates: a build and a test run of one
 * scheme, whatever their selections, build the same code.
 */
export function withConcurrencyOnce(outcome: Report, scope: string, given: Map<string, number>): Report {
  const counted = outcome.concurrency
  const scheme = schemeOfScope(scope)
  if (!counted || !givesConcurrency(given.get(scheme), counted.count)) return outcome
  given.set(scheme, counted.count)
  return { ...outcome, notes: [...outcome.notes, counted.note] }
}

/**
 * Adds the pin's note with the first failure it may explain, and not again: `named` holds the pins Claude has read this
 * session, which it updates.
 */
export function withPinNamedOnce(outcome: Report, named: Set<string>): Report {
  const pin = outcome.pin ?? outcome.pinNote
  if (!outcome.pinNote || !pin || named.has(pin)) return outcome
  named.add(pin)
  return { ...outcome, notes: [...outcome.notes, outcome.pinNote] }
}
