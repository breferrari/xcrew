import { namesTarget, runsEveryTestItNames, type XcodeTool } from './tools'

/**
 * What the next build will use, learned from what the servers answer: MobileBuildMCP's session
 * defaults (Claude calls `session_show_defaults` before its first build) and the Xcode MCP's
 * active scheme and destination. Lives for the session; nothing learned means nothing shown.
 */
type Target = { scheme?: string; destination?: string }

const mobile: { current?: string; profiles: Record<string, { scheme?: string; simulatorName?: string }> } = { profiles: {} }
let xcode: Target = {}

/** Learns from one finished call's output. */
export function observe(tool: XcodeTool, text: string): void {
  // Only these answers name one; parsing every other result would read large outputs for nothing.
  if (!namesTarget(tool)) return
  const json = parse(text)
  if (!json) return
  if (tool.server === 'MobileBuildMCP') {
    const data = json.data as { currentProfile?: string; profiles?: typeof mobile.profiles } | undefined
    if (json.schema === 'mobilebuildmcp.output.session-defaults' && data?.profiles) mobile.profiles = data.profiles
    if (typeof data?.currentProfile === 'string') mobile.current = data.currentProfile
    return
  }
  // XcodeOpenWorkspace says activeScheme; XcodeSwitchScheme says activeSchemeName.
  const scheme = [json.activeScheme, json.activeSchemeName].find(value => typeof value === 'string') as string | undefined
  const destination = [json.activeDestinationDisplayTitle, json.activeRunDestination].find(value => typeof value === 'string') as string | undefined
  if (scheme || destination) xcode = { scheme: scheme ?? xcode.scheme, destination: destination ?? xcode.destination }
}

/** `scheme on destination`, either part alone, or undefined when nothing is known. */
export function describe(tool: XcodeTool, input: Record<string, unknown>): string | undefined {
  const target: Target =
    tool.server === 'MobileBuildMCP'
      ? { scheme: schemeOf(tool, input), destination: (input.simulatorName as string | undefined) ?? profile()?.simulatorName }
      : xcode
  if (target.scheme && target.destination) return `${target.scheme} on ${target.destination}`
  return target.scheme ?? target.destination
}

function profile() {
  return mobile.current === undefined ? undefined : mobile.profiles[mobile.current]
}

/** The scheme the call builds: its own argument, else the profile in use; the Xcode MCP's active one. */
function schemeOf(tool: XcodeTool, input: Record<string, unknown>): string | undefined {
  return tool.server === 'MobileBuildMCP' ? ((input.scheme as string | undefined) ?? profile()?.scheme) : xcode.scheme
}

function parse(text: string): Record<string, unknown> | undefined {
  try {
    const value: unknown = JSON.parse(text)
    return value !== null && typeof value === 'object' ? (value as Record<string, unknown>) : undefined
  } catch {
    return undefined
  }
}

/**
 * What a run's history is kept under: the tool, its scheme, and for a test run the tests
 * `-only-testing` selects (`test_sim · App › SmallTests`), so a small module isn't measured against the whole app.
 */
export function historyOf(tool: XcodeTool, input: Record<string, unknown>): string {
  const scheme = schemeOf(tool, input)
  const extraArgs = Array.isArray(input.extraArgs) ? (input.extraArgs as unknown[]) : []
  const tests = extraArgs.filter((arg): arg is string => typeof arg === 'string' && arg.startsWith('-only-testing:')).map(arg => arg.slice('-only-testing:'.length))
  return `${tool.tool}${scheme ? ` · ${scheme}` : ''}${tests.length > 0 ? ` › ${tests.join(', ')}` : ''}`
}

/**
 * Whether a test run ran every test its scope names, so a pass in it is a pass of each: not one that skips some
 * (`-skip-testing:`), nor an Xcode MCP run of some tests, whose selection the scope doesn't read; only its run of all.
 */
export function runsWholeScope(tool: XcodeTool, input: Record<string, unknown>): boolean {
  const extraArgs = Array.isArray(input.extraArgs) ? (input.extraArgs as unknown[]) : []
  if (extraArgs.some(arg => typeof arg === 'string' && arg.startsWith('-skip-testing:'))) return false
  return runsEveryTestItNames(tool)
}

/** Whether a test run repeats each test (`-test-iterations`), so its result bundle holds each test's runs to read. */
export function isRepeatedRun(input: Record<string, unknown>): boolean {
  return Array.isArray(input.extraArgs) && input.extraArgs.includes('-test-iterations')
}
