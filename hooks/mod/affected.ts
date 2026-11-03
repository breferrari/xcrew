import { joined } from './format'

/**
 * The tests a change can break, for Claude before a full test run: `xcrew affected`'s answer, said so it can be acted
 * on. The selection covers the targets that own or depend on the changed files, as the project declares them, nothing
 * more; anything else runs the whole suite.
 */

/** Behind ToolSearch, as an MCP server's tool is: it costs a session nothing until Claude searches for it. */
export const AFFECTED_TOOL = {
  name: 'affected',
  description:
    'Xcrew: which test targets the changes on this git branch can break, since its merge base with the default branch, uncommitted and untracked files included; with no remote, the uncommitted and untracked files alone. ' +
    'It covers the targets that own or depend on the changed files, as the project declares them; when it can\'t narrow the run, it says so, and why.',
  inputSchema: {
    type: 'object',
    properties: { base: { type: 'string', description: 'A branch or commit to compare with instead of the default branch.' } },
  },
}

/** The full name Claude calls it by: a plugin's registered tool is `mcp__<plugin>__<name>`. */
export const AFFECTED_TOOL_NAME = 'mcp__xcrew__affected'

/** What `xcrew affected` answers. */
export type Affected = { base?: string; changed?: string[]; selections?: string[] | null; runAll?: string | null; uiSelections?: string[]; schemes?: { name: string; container: string; targets: string[] }[]; whole?: Reach; nearest?: Reach[] }

/** A scheme that tests selected targets, as the CLI chose it: those it tests, and how many more. */
export type Reach = { name: string; container: string; tests: string[]; more: number }

export function affectedArgs(input: Record<string, unknown>): string[] {
  return ['affected', ...(typeof input.base === 'string' && input.base !== '' ? ['--base', input.base] : [])]
}

/** Past this many targets of a kind, their `-only-testing:` arguments are too many to use, and aren't given. */
export const ARGUMENTS_UP_TO = 20
/** How many targets of a kind, or of a scheme, are named before the rest are counted. */
export const NAMED_UP_TO = 10
/** Where the whole list is, in a long selection: the CLI's answer, which Claude's Bash and a `!` command both reach. */
const WHOLE_LIST = 'all of them: `xcrew affected` in Bash, or `!xcrew affected` at the prompt'

/** Targets named, as `named` lists them, while they're up to `NAMED_UP_TO`; else counted as `many` words them. */
function namedOrCounted(targets: readonly string[], many: (count: number) => string, named: (targets: readonly string[]) => string = joined): string {
  return targets.length > NAMED_UP_TO ? many(targets.length) : named(targets)
}

/** One kind's targets, with the arguments that run them while they're few enough to use, else a few named and where the rest are. */
function group(targets: readonly string[]): string {
  if (targets.length > ARGUMENTS_UP_TO) return `${targets.slice(0, NAMED_UP_TO).join(', ')} and ${targets.length - NAMED_UP_TO} more; ${WHOLE_LIST}`
  return `${targets.join(', ')} (${targets.map(target => `-only-testing:${target}`).join(' ')})`
}

/**
 * The schemes the CLI chose: past half the suite, the one that tests all of it, alone; else those that test only
 * selected targets, each with its own, the first named and the rest counted, then for each selected target none of
 * them tests, the scheme that tests it with the fewest more, and the targets no shared scheme tests.
 */
function schemesText(affected: Affected, selections: readonly string[]): string {
  if (affected.whole) return ` The changes reach most of the suite: ${schemeName(affected.whole, [])} tests every selected target${affected.whole.more > 0 ? ` and ${affected.whole.more} more` : ''}.`
  const schemes = Array.isArray(affected.schemes) ? affected.schemes : []
  const nearest = Array.isArray(affected.nearest) ? affected.nearest : []
  if (schemes.length === 0 && nearest.length === 0) return ''
  const named = schemes.slice(0, NAMED_UP_TO).map(scheme => `${schemeName(scheme, schemes)} (${namedOrCounted(scheme.targets, count => `${count} targets`, targets => targets.join(', '))})`)
  const list = schemes.length > NAMED_UP_TO ? `${named.join(', ')} and ${schemes.length - NAMED_UP_TO} more; ${WHOLE_LIST}` : joined(named)
  const tested = new Set([...schemes.flatMap(scheme => scheme.targets), ...nearest.flatMap(reach => reach.tests)])
  const untested = selections.filter(target => !tested.has(target))
  const near = nearest.map(reach => `${schemeName(reach, nearest)} tests ${joined(reach.tests)} with ${reach.more} more.`)
  const cover = untested.length > 0 ? [`No shared scheme tests ${namedOrCounted(untested, count => `${count} of the selected targets`)}.`] : near.length === 0 ? ['Between them they test every selected target.'] : []
  return [...(schemes.length > 0 ? [` Schemes that test only selected targets: ${list}.`] : ['']), ...near, ...cover].join(' ')
}

/** A scheme by its name, with its container when another listed beside it has the same name. */
function schemeName(scheme: { name: string; container: string }, beside: readonly { name: string; container: string }[]): string {
  const twin = beside.some(other => other !== scheme && other.name === scheme.name)
  return `\`${scheme.name}\`${twin ? ` in ${scheme.container}` : ''}`
}

/**
 * The answer as Claude reads it, the count first; without one from the CLI, the whole suite, or with `unanswered`, why
 * there's none yet.
 */
export function affectedText(answer: unknown, unanswered?: string): string {
  if (unanswered !== undefined) return `xcrew couldn't say yet which tests the changes can break: ${unanswered}.`
  const affected = (answer ?? {}) as Affected
  const since = affected.base ? ` Compared with ${affected.base}.` : ''
  if (!Array.isArray(affected.selections)) {
    return affected.runAll ? `No narrower selection: ${affected.runAll}; the whole suite covers the changes.${since}` : `xcrew couldn't say which tests the changes can break; the whole suite covers them.${since}`
  }
  const changed = affected.changed?.length ?? 0
  const selections = affected.selections
  if (selections.length === 0) {
    return changed === 0 ? `Nothing has changed, so no tests are affected.${since}` : `No test target covers the ${changed} changed ${changed === 1 ? 'file' : 'files'}, as the project declares them.${since}`
  }
  const ui = new Set(Array.isArray(affected.uiSelections) ? affected.uiSelections : [])
  const uiTargets = selections.filter(target => ui.has(target))
  const unit = selections.filter(target => !ui.has(target))
  const count = `The changes can break ${selections.length} test ${selections.length === 1 ? 'target' : 'targets'}`
  const listed = unit.length > 0 && uiTargets.length > 0
    ? `${count}, ${unit.length} unit and ${uiTargets.length} UI. Unit: ${group(unit)}. UI: ${group(uiTargets)}.`
    : `${count}${uiTargets.length > 0 ? ', all UI' : ''}: ${group(selections)}.`
  return (
    `${listed} They cover the targets that own or depend on the ${changed} changed ${changed === 1 ? 'file' : 'files'}, as the project declares them.${since}` +
    schemesText(affected, selections)
  )
}
