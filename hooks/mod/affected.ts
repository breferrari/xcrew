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
export type Affected = { base?: string; changed?: string[]; selections?: string[] | null; runAll?: string | null; schemes?: { name: string; container: string; targets: string[] }[] }

export function affectedArgs(input: Record<string, unknown>): string[] {
  return ['affected', ...(typeof input.base === 'string' && input.base !== '' ? ['--base', input.base] : [])]
}

/** The shared schemes that test only selected targets, each with its own, and the selected targets none of them tests. */
function schemesText(schemes: Affected['schemes'], selections: readonly string[]): string {
  if (!Array.isArray(schemes) || schemes.length === 0) return ''
  const named = schemes.map(scheme => {
    const twin = schemes.some(other => other !== scheme && other.name === scheme.name)
    return `\`${scheme.name}\`${twin ? ` in ${scheme.container}` : ''} (${scheme.targets.join(', ')})`
  })
  const tested = new Set(schemes.flatMap(scheme => scheme.targets))
  const untested = selections.filter(target => !tested.has(target))
  const cover = untested.length === 0 ? 'Between them they test every selected target.' : `None of them tests ${joined(untested)}.`
  return ` Schemes that test only selected targets: ${joined(named)}. ${cover}`
}

/** The answer as Claude reads it; without one from the CLI, the whole suite. */
export function affectedText(answer: unknown): string {
  const affected = (answer ?? {}) as Affected
  const since = affected.base ? ` Compared with ${affected.base}.` : ''
  if (!Array.isArray(affected.selections)) {
    return affected.runAll ? `No narrower selection: ${affected.runAll}; the whole suite covers the changes.${since}` : `xcrew couldn't say which tests the changes can break; the whole suite covers them.${since}`
  }
  const changed = affected.changed?.length ?? 0
  if (affected.selections.length === 0) {
    return changed === 0 ? `Nothing has changed, so no tests are affected.${since}` : `No test target covers the ${changed} changed ${changed === 1 ? 'file' : 'files'}, as the project declares them.${since}`
  }
  return (
    `The changes can break these test targets: ${affected.selections.join(', ')} (${affected.selections.map(target => `-only-testing:${target}`).join(' ')}). ` +
    `They cover the targets that own or depend on the ${changed} changed ${changed === 1 ? 'file' : 'files'}, as the project declares them.${since}` +
    schemesText(affected.schemes, affected.selections)
  )
}
