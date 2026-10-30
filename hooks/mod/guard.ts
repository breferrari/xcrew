import type { Generated } from './cli'

/**
 * The words of the guard on edits to generated projects. A generator rewrites its project, its workspace and, for Tuist,
 * its `Derived` folder on every generate, so an edit there is lost. The person decides: the call is held while they're
 * asked, and refused with the reason when they choose the manifest instead, or when there's nobody to ask. In a classic
 * Xcode project nothing is held: XcodeWrite is how a new file joins its target there.
 */

const REASON =
  'xcrew: this project is generated (Tuist or XcodeGen), and XcodeWrite re-saves the whole generated project file. ' +
  'Create the file with the Write tool instead; the generator picks it up.'

const NOTE = 'This project is generated (Tuist or XcodeGen): this tool re-saves the generated project, so the person is asked first. Create files with the Write tool instead.'

/** Saying so in the description saves Claude the held call. */
export function describedForGenerated(description: string): string {
  return `${description}\n\n${NOTE}`
}

/** A question to the person: what's asked, the header chip, and the option that lets the call run first. */
export type Question = { question: string; header: string; options: [allow: string, instead: string] }

export const XCODE_WRITE_QUESTION: Question = {
  question: 'XcodeWrite re-saves the whole generated project, which the next generate overwrites. Let it, or have Claude write the file with Write instead?',
  header: 'Generated',
  options: ['Let XcodeWrite save it', 'Use Write instead'],
}

/** The question before an edit to a file a generator writes. */
export function editQuestion(file: string, generated: Generated): Question {
  return {
    question: `${file} is generated: the next \`${generated.generate}\` overwrites this edit. Edit it anyway, or edit ${generated.manifest} instead?`,
    header: 'Generated',
    options: ['Edit the generated file', `Edit ${generated.manifest} instead`],
  }
}

/** Why an edit to a generated file was refused, with what the person typed when they answered in their own words. */
export function editRefusal(file: string, generated: Generated, said?: string): string {
  const reason = `xcrew: ${file} is generated from ${generated.manifest}, and the next \`${generated.generate}\` overwrites an edit to it. Edit ${generated.manifest} instead, then run \`${generated.generate}\`.`
  return withSaid(reason, said)
}

/** XcodeWrite's refusal, with what the person typed when they answered in their own words. */
export function xcodeWriteRefusal(said?: string): string {
  return withSaid(REASON, said)
}

function withSaid(reason: string, said: string | undefined): string {
  return said ? `${reason} The person said: ${said}` : reason
}

/**
 * What an answer means: run the call, or refuse it, with the person's own words when they typed them. Nobody to ask
 * (`undefined`) refuses, as the guard did before it asked.
 */
export function decided(question: Question, answer: string | undefined): { allows: true } | { allows: false; said?: string } {
  if (answer === question.options[0]) return { allows: true }
  return answer === undefined || answer === question.options[1] || answer.trim() === '' ? { allows: false } : { allows: false, said: answer }
}
