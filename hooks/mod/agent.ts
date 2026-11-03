/** How many characters of a subagent's description a run's `by` keeps, counted as a reader counts them. */
const KEPT = 40

/**
 * A subagent's own description, as the run it started shows it: as given, on one line, cut after `KEPT` characters.
 * None for a description that says nothing: no type, name or id stands in for it.
 */
export function shortDescription(description: string | undefined): string | undefined {
  const words = [...(description ?? '')].map(character => character.trim() || ' ').join('').split(' ').filter(word => word !== '')
  const characters = [...new Intl.Segmenter().segment(words.join(' '))].map(part => part.segment)
  if (characters.length === 0) return undefined
  return characters.length > KEPT ? `${characters.slice(0, KEPT).join('').trimEnd()}…` : characters.join('')
}
