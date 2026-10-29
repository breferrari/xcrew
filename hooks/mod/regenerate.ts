import type { StaleProject } from '../../types'
import { generatedApps } from './tools'

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

type Mark = StaleProject['marks'][number]

/** The marks of a stale project, or none: a session that began on an older mod may hold another shape. */
export function marksOf(stale: StaleProject | null | undefined): readonly Mark[] {
  return Array.isArray(stale?.marks) ? stale.marks : []
}

/**
 * The marks after an edit to an app's manifests: one per app, and a build refused again for it. Of two commands for
 * the app, the one that holds the other stays, so an install a dependency edit needs isn't lost to a later edit.
 */
export function marked(stale: StaleProject | null, mark: Mark): StaleProject {
  const earlier = marksOf(stale).find(other => other.app === mark.app)
  const generate = earlier?.generate.includes(mark.generate) ? earlier.generate : mark.generate
  return { marks: [...marksOf(stale).filter(other => other.app !== mark.app), { app: mark.app, generate }], refused: false }
}

/**
 * The marks after a generate that succeeded: each app it names is up to date, matched by its path from the root or a
 * longer path ending in it; one generate that names none may have run in any app, and clears them all. A build is
 * refused again for the marks left.
 */
export function afterGenerate(stale: StaleProject | null, command: string): StaleProject | null {
  const ran = generatedApps(command)
  const isGenerated = (app: string) => ran.some(path => path === undefined || path === app || (app !== '' && path.endsWith(`/${app}`)))
  const left = marksOf(stale).filter(mark => !isGenerated(mark.app))
  return left.length > 0 ? { marks: left, refused: false } : null
}
