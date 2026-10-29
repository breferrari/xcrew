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
export function refusal(generate: string): string {
  return (
    `xcrew: the project's manifests changed since it was last generated, so this would build the project as it was. ` +
    `Run \`${generate}\` from the project's root, then try again. If the person regenerated it already, try again: it goes through.`
  )
}

/** What Claude reads after the build it tried again without a generate. */
export function letThroughNote(generate: string): string {
  return `xcrew: this ran without \`${generate}\` after a manifest edit, taken as regenerated outside this session; if its errors name what the edit changed, run it.`
}
