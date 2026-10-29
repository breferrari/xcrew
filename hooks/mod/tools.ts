/**
 * Which tool calls the mod acts on. Names are matched without their server prefix, so the same
 * rules hold whether a tool comes from this plugin's server (`mcp__plugin_xcrew_xcode__…`) or
 * from one the person registered themselves (`mcp__xcode__…`).
 */

/** Matches a tool's full name under both registrations: this plugin's server, and the person's own. */
function bothRegistrations(server: string, tools: readonly string[]): RegExp {
  return new RegExp(`^mcp__(?:plugin_xcrew_)?${server}__(?:${tools.join('|')})$`)
}

/** The matcher for the guard: the engine calls a hook only for the tools its matcher matches. */
export const PROJECT_REWRITER = bothRegistrations('xcode', ['XcodeWrite'])

/**
 * Whether a tool's answer can name what the next build will use: any of MobileBuildMCP's session
 * tools, and the Xcode MCP's workspace and switch tools. By family, so a tool either server adds
 * there later is read too; a file another tool returns is never mistaken for one.
 */
export function namesTarget(tool: XcodeTool): boolean {
  return tool.server === 'MobileBuildMCP' ? /^session_/.test(tool.tool) : /^Xcode(OpenWorkspace|Switch\w+)$/.test(tool.tool)
}

/** `mcp__<server>__<tool>`, where server is `xcode`, `MobileBuildMCP`, or either under this plugin. */
const MCP_TOOL = /^mcp__(?:plugin_xcrew_)?(xcode|MobileBuildMCP)__(\w+)$/

export type ToolKind = 'build' | 'test' | 'run'

export type XcodeTool = { server: 'xcode' | 'MobileBuildMCP'; tool: string }

export function parseTool(name: string): XcodeTool | undefined {
  const match = MCP_TOOL.exec(name)
  const [, server, tool] = match ?? []
  return server && tool ? { server: server as XcodeTool['server'], tool } : undefined
}

/**
 * A tool name's words, lowercased and spaced: split at `_`, where a lowercase letter or digit meets a
 * capital, and before the last capital of an acronym (`RunUITests` → `run ui tests`).
 */
function wordsOf(name: string): string {
  return name.replace(/([a-z0-9])([A-Z])/g, '$1 $2').replace(/([A-Z]+)([A-Z][a-z])/g, '$1 $2').replace(/_/g, ' ').toLowerCase()
}

/**
 * Whether a call is a build, a test run or an app run worth timing. Matched by whole words rather
 * than a list, so tools either server adds later are timed without a change here. A tool that only
 * reads, by its verb, or that names what the next build uses, isn't timed whatever else its name says.
 */
export function kindOf(tool: XcodeTool): ToolKind | undefined {
  const words = wordsOf(tool.tool)
  if (namesTarget(tool) || /\b(get|list|show|read|describe|status|settings)\b/.test(words)) return undefined
  if (/\btest(s|ing)?\b/.test(words)) return 'test'
  if (/\b(build|clean)\b/.test(words)) return 'build'
  if (/\brun (project|app)\b|\blaunch\b|\binstall and run\b/.test(words)) return 'run'
  return undefined
}

