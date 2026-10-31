import type { CliBuild, ElsewhereRun, FailureList } from '../../types'

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
  /** The task a call moved to the background answers with, which its notification names. */
  backgroundTask?: string
  /** The outcome is a run log's last verdict alone, with no test's own result read. */
  isVerdictOnly?: boolean
  /** Why the run failed when the cause is the Mac, with its fix: the note that leads `notes`, for the pane to open with. */
  cause?: string
  /** The run's Swift concurrency diagnostics when its log holds many: how many, and the note that gives their counts. */
  concurrency?: { count: number; note: string }
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

/** The scheme MobileBuildMCP builds with when a call names none, as `xcrew project --profiles` answers. */
export function profileSchemeOf(answer: unknown): string | undefined {
  const scheme = (answer as { scheme?: unknown } | undefined)?.scheme
  return typeof scheme === 'string' && scheme !== '' ? scheme : undefined
}

/** Xcode's selection at MobileBuildMCP's start, as `xcrew project --xcode` answers when Xcode hosts its server. */
export function xcodeSelectionOf(answer: unknown): { state: string; scheme?: string; follows: boolean; activeProfile?: string } | undefined {
  const read = answer as { xcodeState?: unknown; followsXcode?: unknown; activeProfile?: unknown } | undefined
  if (typeof read?.xcodeState !== 'string') return undefined
  return {
    state: read.xcodeState,
    follows: read.followsXcode === true,
    ...(xcodeSchemeOf(answer) === undefined ? {} : { scheme: xcodeSchemeOf(answer) }),
    ...(typeof read.activeProfile === 'string' ? { activeProfile: read.activeProfile } : {}),
  }
}

/** Whether Xcode started MobileBuildMCP's server, as `xcrew project --xcode` answers; undefined while no server is found. */
export function xcodeHostsServerOf(answer: unknown): boolean | undefined {
  const hosts = (answer as { xcodeHostsServer?: unknown } | undefined)?.xcodeHostsServer
  return typeof hosts === 'boolean' ? hosts : undefined
}

/** The other worktrees' runs, as `xcrew runs` answers; undefined when it didn't answer a list. */
export function elsewhereOf(answer: unknown): ElsewhereRun[] | undefined {
  if (!Array.isArray(answer)) return undefined
  return answer.flatMap(run => {
    const { worktree, tool, phase } = (run ?? {}) as { worktree?: unknown; tool?: unknown; phase?: unknown }
    if (typeof worktree !== 'string' || typeof tool !== 'string') return []
    return [{ worktree, tool, ...(typeof phase === 'string' && phase !== '' ? { phase } : {}) }]
  })
}

/** The scheme selected in Xcode, as `xcrew project --xcuserstate <file>` answers. */
export function xcodeSchemeOf(answer: unknown): string | undefined {
  const scheme = (answer as { xcodeScheme?: unknown } | undefined)?.xcodeScheme
  return typeof scheme === 'string' && scheme !== '' ? scheme : undefined
}

/** The line offering setup, as `xcrew project --profiles` answers while MobileBuildMCP has no scheme to build with. */
export function setupOfferOf(answer: unknown): string | undefined {
  const setup = (answer as { setup?: unknown } | undefined)?.setup
  return typeof setup === 'string' && setup !== '' ? setup : undefined
}

/** A file's content hash as `xcrew project --hash` answers: empty for a file that isn't there; none when it couldn't say. */
export function hashOf(answer: unknown): string | undefined {
  const { hash } = (answer ?? {}) as { hash?: unknown }
  return typeof hash === 'string' ? hash : undefined
}

/** The notes `xcrew note` has for a tool's result; none when it couldn't answer. */
export function notesOf(answer: unknown): string[] {
  const { notes } = (answer ?? {}) as { notes?: unknown }
  return Array.isArray(notes) ? notes.filter((note): note is string => typeof note === 'string') : []
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
