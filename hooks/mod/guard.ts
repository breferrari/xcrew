import type { On } from 'claude-code'
import { isGeneratedProject } from './cli'
import { PROJECT_REWRITER } from './tools'

const REASON =
  'xcrew: this project is generated (Tuist or XcodeGen), and XcodeWrite re-saves the whole generated project file. ' +
  'Create the file with the Write tool instead; the generator picks it up.'

const NOTE = 'This project is generated (Tuist or XcodeGen), so this tool is refused here: create files with the Write tool instead.'

/**
 * Refuses the Xcode MCP's file writer in generated projects only. In a classic Xcode project,
 * XcodeWrite is how a new file joins its target, so it stays allowed there.
 */
export function registerGuard(on: On): void {
  on('tool.call', { tool: PROJECT_REWRITER }, async ($, e, next) => ((await isGeneratedProject($)) ? { deny: REASON } : next(e)))
  // Saying so in the description saves Claude the refused call.
  on('tool.describe', { tool: PROJECT_REWRITER }, async ($, e, next) => {
    const described = await next(e)
    return (await isGeneratedProject($)) ? { ...described, description: `${described.description}\n\n${NOTE}` } : described
  })
}
