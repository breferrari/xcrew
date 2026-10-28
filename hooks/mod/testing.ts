import type { Engine } from 'claude-code/testing'
import type { ToolCallArgs, ToolCallResult } from 'claude-code'

/**
 * Calls a tool by its full name. The generated types know only the MCP servers connected when the
 * mod last loaded, which differs per machine, so the name stays untyped here.
 */
export function callTool($: Engine, tool: string, args: Record<string, unknown> = {}): Promise<ToolCallResult> {
  return $.tool.call({ tool, ...args } as unknown as ToolCallArgs)
}

/** Runs a slash command as the person would from the prompt. */
export function runCommand($: Engine, command: string, args = '') {
  return $.command.run({ command, args, origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 100 } })
}
