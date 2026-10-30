import type { CliBuild, FailureList } from '../../types'

/**
 * The mod's protocol with the Swift CLI, which reads and parses everything the servers print: which
 * program to run, with which arguments and time, and what its answer means. The mod hands it text and
 * gets JSON back; see the mod's rule in docs/architecture.md. The hooks module starts the program.
 */

/** One failing test or compile error, for the failure pane; the state contract declares its shape. */
export type Failure = FailureList['items'][number]

/** A repeated test as `xcrew report` counts it, with its verdict: the CLI decides flaky or real, the mod only keeps it. */
export type Repetition = { test: string; failed: number; passed: number; runs: number; verdict: 'flaky' | 'real' | 'passed' | 'none' }

/** What `xcrew report` makes of a finished build, test or run call. */
export type Report = {
  ok: boolean
  detail?: string
  durationMs?: number
  tests?: number
  failures: Failure[]
  /** What Claude reads in place of the server's result; absent keeps the server's. */
  result?: string
  notes: string[]
  /** For a run repeated with `-test-iterations`: each repeated test's runs, and the verdict the CLI gives them. */
  repeated?: Repetition[]
  /** The result said no outcome, as a call moved to the background answers with a handle. */
  isUnread?: boolean
  /** A test run's result bundle. */
  bundle?: string
  /** That another Xcode than the pin's built, for a failure whose errors another SDK or toolchain gives. */
  pinNote?: string
  /** The pin it names, which the mod names once a session. */
  pin?: string
}

/** What `xcrew phase` says of a running MobileBuildMCP call. */
export type Phase = { log?: string; phase?: string }

/** One line of `xcrew doctor --problems --json`. */
export type Problem = { status: 'fail' | 'warn'; id: string; message: string }

/** A finished program's output, as the hooks module hands it back. */
export type Ran = { stdout: string; stderr: string }

/** How long the shim's answer is trusted before asking again: a development checkout rebuilds when its sources change. */
const RECHECK_MS = 30_000


export function shimPath(pluginRoot: string): string {
  return `${pluginRoot}/bin/xcrew`
}

/** The build to run while the shim's last answer is fresh; `ask` when it's stale or there is none. */
export function knownBuild(known: CliBuild | null, now: number): string | undefined | 'ask' {
  if (known && now >= known.at && now - known.at < RECHECK_MS) return known.path ?? undefined
  return 'ask'
}

/** Only a path to a build counts: anything else on stdout leaves the CLI to the shim. */
export function namedBuild(stdout: string): string | null {
  const path = stdout.trim()
  return path.startsWith('/') && path.endsWith('/xcrew') ? path : null
}

/** A command that ran out of time isn't started again through the shim, which would double the wait. */
export function ranOutOfTime(startedAt: number, now: number, timeoutMs: number): boolean {
  return now - startedAt >= timeoutMs
}

export function reportArgs(server: string, kind: string, isError: boolean, repeated = false): string[] {
  return ['report', '--server', server, '--kind', kind, ...(isError ? ['--error'] : []), ...(repeated ? ['--repeated'] : [])]
}

export function phaseArgs(tool: string, since: number, expectedTests: number | undefined, log: string | undefined): string[] {
  return ['phase', '--tool', tool, '--since', String(since), ...(expectedTests === undefined ? [] : ['--expected', String(expectedTests)]), ...(log === undefined ? [] : ['--log', log])]
}

/** The CLI's JSON answer, or nothing when it didn't run or said something else. */
export function answerOf(ran: Ran | undefined): unknown {
  if (!ran) return undefined
  try {
    return JSON.parse(ran.stdout)
  } catch {
    return undefined
  }
}

/** The report for a finished call; without one, the outcome is whether the server reported an error. */
export function reportOf(answer: unknown, isError: boolean): Report {
  const parsed = (answer ?? {}) as Partial<Report>
  return { ...parsed, ok: parsed.ok ?? !isError, failures: parsed.failures ?? [], notes: parsed.notes ?? [] }
}

/** The running call's log, once it appears, and the phase read from it. */
export function phaseOf(answer: unknown): Phase {
  return (answer as Phase | undefined) ?? {}
}

/** What `xcrew doctor` finds wrong, worst first; nothing outside an Apple-platform project. */
export function problemsOf(answer: unknown): Problem[] {
  return (answer as Problem[] | undefined) ?? []
}

/** Whether Tuist or XcodeGen generates this project; false when the CLI can't say, which leaves XcodeWrite allowed. */
export function isGeneratedOf(answer: unknown): boolean {
  return (answer as { isGenerated?: boolean } | undefined)?.isGenerated === true
}

/** The line offering setup, as `xcrew project --profiles` answers while MobileBuildMCP has no scheme to build with. */
export function setupOfferOf(answer: unknown): string | undefined {
  const setup = (answer as { setup?: unknown } | undefined)?.setup
  return typeof setup === 'string' && setup !== '' ? setup : undefined
}

/** The app an edit changed and the command that regenerates it, when the file `xcrew project --manifest` was asked about is a manifest. */
export function manifestEditOf(answer: unknown): { app: string; generate: string } | undefined {
  const { app, generate } = (answer ?? {}) as { app?: unknown; generate?: unknown }
  return typeof app === 'string' && typeof generate === 'string' && generate !== '' ? { app, generate } : undefined
}

/** Where a checkout stands, as `xcrew project --branch` answers: its real root, and its branch, or its commit when HEAD is detached. */
export type Head = { root: string; branch?: string; commit?: string }

/** What `xcrew project --branch` answered, when it named a root. */
export function headOf(answer: unknown): Head | undefined {
  const { root, branch, commit } = (answer ?? {}) as Record<string, unknown>
  if (typeof root !== 'string' || root === '') return undefined
  return { root, ...(typeof branch === 'string' ? { branch } : {}), ...(typeof commit === 'string' ? { commit } : {}) }
}

/** The manifest to edit instead of a generated file and the command that regenerates it, when `xcrew project --generated` named one. */
/** A file a generator writes: the manifest to edit instead, and the command that regenerates it. */
export type Generated = { manifest: string; generate: string }

export function generatedOf(answer: unknown): Generated | undefined {
  const { manifest, generate } = (answer ?? {}) as { manifest?: unknown; generate?: unknown }
  return typeof manifest === 'string' && typeof generate === 'string' ? { manifest, generate } : undefined
}

/** Why a CLI command couldn't run. */
export function couldntRun(args: readonly string[], error: unknown): string {
  return `xcrew ${args.join(' ')} couldn't run: ${error instanceof Error ? error.message : String(error)}`
}
