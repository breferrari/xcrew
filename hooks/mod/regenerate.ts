import type { StaleProject } from '../../types'
import { generatedApp } from './tools'

/**
 * Builds after a manifest edit. The generated project changes only when the generator runs again, so a build before
 * that builds the project as it was, and its errors don't say why. Tuist rewrites only the files whose content changed,
 * so file times can't tell a stale project from a current one (docs/findings.md): the mark comes from what this
 * session did. The first build after an edit is refused once; the next goes through, since the person may have
 * regenerated in their own terminal, which the mod can't see.
 */

/** What Claude reads after editing a manifest. */
export function editedNote(generate: string): string {
  return `xcrew: this is one of the project's manifests, so the generated project changes only after \`${generate}\`: run it from the project's root before the next build or test.`
}

/** Why the first build or test after a manifest edit is refused. */
export function refusal(generates: readonly string[]): string {
  return (
    `xcrew: the project's manifests changed since it was last generated, so this would build the project as it was. ` +
    `Run ${listed(generates)} from the project's root, then try again. If the person regenerated it already, try again: it goes through.`
  )
}

/** What Claude reads after the build it tried again without a generate. */
export function letThroughNote(generates: readonly string[]): string {
  return `xcrew: this ran without ${listed(generates)} after a manifest edit, taken as regenerated outside this session; if its errors name what the edit changed, run ${generates.length > 1 ? 'them' : 'it'}.`
}

/** The commands in code, one after another: `a`, `b` and `c`. */
function listed(generates: readonly string[]): string {
  const quoted = generates.map(generate => `\`${generate}\``)
  return quoted.length > 1 ? `${quoted.slice(0, -1).join(', ')} and ${quoted.at(-1)}` : (quoted[0] ?? '')
}

/** The marks after an edit to a manifest `generate` regenerates: one per app, and a build refused again for the new one. */
export function marked(stale: StaleProject | null, generate: string): StaleProject {
  return { generates: [...(stale?.generates ?? []).filter(other => other !== generate), generate], refused: false }
}

/**
 * The marks after a generate that succeeded: the app it names is up to date; one that names none may have run in any,
 * after a `cd`, and clears them all. A build is refused again for the marks left.
 */
export function afterGenerate(stale: StaleProject | null, command: string): StaleProject | null {
  const app = generatedApp(command)
  const left = app === undefined ? [] : (stale?.generates ?? []).filter(generate => generatedApp(generate) !== app)
  return left.length > 0 ? { generates: left, refused: false } : null
}
