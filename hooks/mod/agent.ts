/** How many characters of a subagent's description a run's label keeps. */
const KEPT = 40

/**
 * A subagent's own description as the label of a run it started: as given, on one line, cut after `KEPT` characters.
 * None for a description that says nothing: no type, name or id stands in for it.
 */
export function agentLabelOf(description: string | undefined): string | undefined {
  const line = [...(description ?? '')].map(character => (character.trim() === '' ? ' ' : character)).join('').split(' ').filter(word => word !== '').join(' ')
  if (line === '') return undefined
  return line.length > KEPT ? `${line.slice(0, KEPT).trimEnd()}…` : line
}

/** `by "Fix login tests"`: the label as the band and the row draw it, quoted, since the words are the agent's. */
export function byText(label: string): string {
  return `by "${label}"`
}
