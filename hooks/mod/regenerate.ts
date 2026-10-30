import type { StaleProject } from '../../types'
import { generatedApps } from './tools'
import { joined } from './format'

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
  return joined(generates.map(generate => `\`${generate}\``))
}

type Mark = StaleProject['marks'][number]

/** The marks of a stale project, or none: a session that began on an older mod may hold another shape. */
export function marksOf(stale: StaleProject | null | undefined): readonly Mark[] {
  return Array.isArray(stale?.marks) ? stale.marks : []
}

/**
 * The marks after an edit to an app's manifests: one per app, and a build refused again for it. Of two commands for
 * the app, the one that holds the other stays, so an install a dependency edit needs isn't lost to a later edit. The
 * mark keeps each edited file's hash from before its first edit since the last generate (`before`, null when it couldn't
 * be read), so an edit undone can be told.
 */
export function marked(stale: StaleProject | null, mark: { app: string; generate: string }, file?: { path: string; before: string | null }): StaleProject {
  const earlier = marksOf(stale).find(other => other.app === mark.app)
  const generate = earlier?.generate.includes(mark.generate) ? earlier.generate : mark.generate
  // An earlier edit without its hash, as an older mod marked one, can't be told undone: nor can the mark, whatever follows.
  const files = earlier && !earlier.files ? (file ? { [file.path]: null } : {}) : { ...(file && { [file.path]: file.before }), ...earlier?.files }
  const kept = { app: mark.app, generate, ...(Object.keys(files).length > 0 ? { files } : {}), ...(earlier?.wasRefused ? { wasRefused: true as const } : {}) }
  return { marks: [...marksOf(stale).filter(other => other.app !== mark.app), kept], refused: false }
}

/**
 * Whether a mark's edits are all undone: each file it holds has the hash it had before its first edit, `now` giving
 * the hashes read now. A file whose hash couldn't be read, then or now, leaves the edit standing, and so does a mark a
 * build was refused for: the person may have generated from the edit since.
 */
export function isUndone(mark: Mark, now: Readonly<Record<string, string | undefined>>): boolean {
  const files = Object.entries(mark.files ?? {})
  return !mark.wasRefused && files.length > 0 && files.every(([path, before]) => now[path] === before)
}

/** The stale project as a refusal leaves it: each mark refused for, and the next build let through. */
export function refused(stale: StaleProject | null): StaleProject | null {
  return stale && { marks: marksOf(stale).map(mark => ({ ...mark, wasRefused: true as const })), refused: true }
}

/**
 * The stale project without the marks found undone, as they were when read: a mark changed since, by an edit meanwhile,
 * stays. Null when none is left.
 */
export function withoutUndone(stale: StaleProject | null, undone: readonly Mark[]): StaleProject | null {
  const same = (mark: Mark) => undone.some(gone => JSON.stringify(gone) === JSON.stringify(mark))
  const left = marksOf(stale).filter(mark => !same(mark))
  return left.length > 0 && stale ? { ...stale, marks: left } : null
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
