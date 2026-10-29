/**
 * The XcodeWrite guard's words. It refuses the Xcode MCP's file writer in generated projects only:
 * in a classic Xcode project, XcodeWrite is how a new file joins its target, so it stays allowed there.
 */

export const REASON =
  'xcrew: this project is generated (Tuist or XcodeGen), and XcodeWrite re-saves the whole generated project file. ' +
  'Create the file with the Write tool instead; the generator picks it up.'

const NOTE = 'This project is generated (Tuist or XcodeGen), so this tool is refused here: create files with the Write tool instead.'

/** Saying so in the description saves Claude the refused call. */
export function describedForGenerated(description: string): string {
  return `${description}\n\n${NOTE}`
}
