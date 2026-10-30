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

/** Forgets what the Xcode MCP has active after a call that may have changed it but whose answer can't be read. */
export function lost(tool: XcodeTool): void {
  if (tool.server === 'xcode' && namesTarget(tool)) xcode = {}
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
  const tests = selectedTests(input)
  return `${tool.tool}${scheme ? ` · ${scheme}` : ''}${tests.length > 0 ? ` › ${tests.join(', ')}` : ''}`
}

/** The tests a run's `-only-testing:` arguments select; none when it runs its scheme's whole suite. */
export function selectedTests(input: Record<string, unknown>): string[] {
  const extraArgs = Array.isArray(input.extraArgs) ? (input.extraArgs as unknown[]) : []
  return extraArgs.filter((arg): arg is string => typeof arg === 'string' && arg.startsWith('-only-testing:')).map(arg => arg.slice('-only-testing:'.length))
}

/**
 * `xcodebuild` options that narrow a test run to part of its scheme or run its tests more than once, besides
 * `-only-testing:`, `-skip-testing:` and `-test-iterations`. A fixed list, as `man xcodebuild` names them; a test pins it.
 */
export const NARROWING_OR_REPEATING = ['-only-test-configuration', '-skip-test-configuration', '-testPlan', '-retry-tests-on-failure', '-run-tests-until-failure']

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

/**
 * Whether a test run is the whole suite: it ran every test its tool and scheme name, with no `-only-testing:` selection,
 * once each. What the loop budget counts.
 */
export function isFullSuiteRun(tool: XcodeTool, input: Record<string, unknown>): boolean {
  const extraArgs = Array.isArray(input.extraArgs) ? (input.extraArgs as unknown[]) : []
  const narrows = extraArgs.some(arg => typeof arg === 'string' && NARROWING_OR_REPEATING.includes(arg))
  return selectedTests(input).length === 0 && !narrows && !isRepeatedRun(input) && runsWholeScope(tool, input)
}
