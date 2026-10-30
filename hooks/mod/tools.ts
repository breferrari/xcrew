/**
 * Which tool calls the mod acts on. Names are matched without their server prefix, so the same
 * rules hold whether a tool comes from this plugin's server (`mcp__plugin_xcrew_xcode__…`) or
 * from one the person registered themselves (`mcp__xcode__…`).
 */

/** Matches a tool's full name under both registrations: this plugin's server, and the person's own. */
function bothRegistrations(server: string, tools: readonly string[]): RegExp {
  return new RegExp(`^mcp__(?:plugin_xcrew_)?${server}__(?:${tools.join('|')})$`)
}

/** A shell command that runs `xcrew setup`, by any path to the CLI, quoted or not, alone or among other commands. */
const SETUP_COMMAND = /(?:^|[\s;&|(])["']?(?:[^\s"']*\/)?xcrew["']?\s+setup(?:[\s;&|)]|$)/

export function runsSetup(command: string): boolean {
  return SETUP_COMMAND.test(command)
}

/** The built-in tools that change a file's text; an edit to a manifest leaves the generated project behind it. */
export const FILE_EDITOR = /^(?:Write|Edit)$/

/**
 * A name a generator may read: Tuist's markers and manifests, any file in its `Tuist/` folder, and any YAML file,
 * since XcodeGen's spec may include others by any name. In any case, as the file system matches names. Only a first
 * look, so most edits never start the CLI, which decides.
 */
const MANIFEST_NAME = /(?:^|\/)(?:(?:Tuist|Project|Workspace)\.swift|[^/]+\.ya?ml|Tuist\/.+)$/i

export function mayBeManifest(path: string): boolean {
  return MANIFEST_NAME.test(path)
}

/**
 * A path inside a folder a generator may write: a project or workspace bundle, or Tuist's `Derived` folder, named as
 * the CLI matches them. Only a first look, so most edits never start the CLI, which decides.
 */
const GENERATED_PATH = /(?:^|\/)(?:[^/]+\.(?:xcodeproj|xcworkspace)|Derived)\//

export function mayBeGenerated(path: string): boolean {
  return GENERATED_PATH.test(path)
}

/** `tuist generate`, or `xcodegen` with its default `generate` or none, by any path to the program, which it captures. */
const GENERATE_COMMAND = /(?:^|[\s;&|(])["']?(?:[^\s"']*\/)?(?:(tuist)["']?\s+generate|(xcodegen)["']?(?:\s+generate)?(?!\s+[a-z]))(?=[\s;&|)]|$)/g

/** One generate in a shell command: its program, and the command before and after it. */
type Generate = { program: 'tuist' | 'xcodegen'; before: string; after: string }

/** Every generate a shell command runs, in order. */
function generatesIn(command: string): Generate[] {
  return [...command.matchAll(GENERATE_COMMAND)].map(match => ({
    program: match[1] ? 'tuist' : 'xcodegen',
    before: command.slice(0, match.index),
    after: command.slice(match.index + match[0].length),
  }))
}

/**
 * Whether a shell command regenerates the project, and its exit status says whether that worked: nothing after the
 * first generate but redirections, `&&` and more of it, since a later command's status, in a pipe or after `;`, would
 * hide a failure.
 */
export function runsGenerate(command: string): boolean {
  const [first] = generatesIn(command)
  return first !== undefined && !/[|;&\n]/.test(first.after.replace(/\d*>&\d+|&&/g, ' '))
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
export const MCP_TOOL = /^mcp__(?:plugin_xcrew_)?(xcode|MobileBuildMCP)__(\w+)$/

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


/**
 * Whether a call builds the project, so a stale one would build it as it was: a build, a test run, or a run that builds
 * first (`RunProject`); not a clean, nor a launch of what was built.
 */
export function buildsProject(tool: XcodeTool): boolean {
  const kind = kindOf(tool)
  const words = wordsOf(tool.tool)
  if (kind === 'build') return !/\bclean\b/.test(words)
  if (kind === 'run') return !/\blaunch\b/.test(words)
  return kind === 'test'
}

/** The option naming the app each generator reads: Tuist's folder, and XcodeGen's spec, whose folder is the app's. */
const APP_OPTION = {
  tuist: /(?:^|\s)(?:--path|-p)(?:=|\s+)('[^']*'|"[^"]*"|\S+)/,
  xcodegen: /(?:^|\s)(?:--spec|-s)(?:=|\s+)('[^']*'|"[^"]*"|\S+)/,
} as const
/** A `cd` into a folder just before the generate, joined by `&&`. */
const CD_BEFORE = /(?:^|[;&|(]\s*)cd\s+('[^']*'|"[^"]*"|[^\s;&|]+)\s*&&\s*$/

/**
 * The app each generate in a shell command is for, as the path its option or a `cd` before it gives: `apps/b` for
 * `--path ./apps/b/`. Nothing for one that names none, which may have run anywhere.
 */
export function generatedApps(command: string): (string | undefined)[] {
  return generatesIn(command).map(({ program, before, after }) => {
    const named = APP_OPTION[program].exec(after.split(/[;&|\n]/)[0] ?? '')?.[1]
    const path = named ?? CD_BEFORE.exec(before)?.[1]
    if (path === undefined) return undefined
    const unquoted = path.replace(/^(['"])(.*)\1$/, '$2').replace(/^\.\//, '')
    const folder = (named !== undefined && program === 'xcodegen' ? unquoted.replace(/\/?[^/]*$/, '') : unquoted).replace(/\/+$/, '')
    return folder === '' || folder === '.' ? undefined : folder
  })
}

/**
 * Whether a test tool runs every test its scope names: MobileBuildMCP's, whose selection the scope reads from its
 * arguments, and the Xcode MCP's run of all tests. Its other test tools take a selection the scope doesn't read.
 */
export function runsEveryTestItNames(tool: XcodeTool): boolean {
  return tool.server !== 'xcode' || /\ball\b/.test(wordsOf(tool.tool))
}

/** A generated file's path from its bundle or `Derived` folder on, as the person reads it: `App.xcodeproj/project.pbxproj`. */
export function generatedPart(path: string): string {
  const match = GENERATED_PATH.exec(path)
  return match ? path.slice(match.index + (match[0].startsWith('/') ? 1 : 0)) : path
}
