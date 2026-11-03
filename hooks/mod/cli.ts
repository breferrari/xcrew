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

/**
 * A flaky mark as `xcrew flaky` answers it after a repeated run: the failures and runs of the repeated runs up to its
 * last failure, the passes in a row since, the passes needed, and whether it has them. The CLI works them out.
 */
export type FlakyMark = { test: string; failed: number; runs: number; passes: number; needed: number; settled: boolean }

/** `xcrew flaky`'s marks, or none when it couldn't answer. */
export function flakyMarksOf(answer: unknown): FlakyMark[] | undefined {
  return Array.isArray(answer) ? (answer as FlakyMark[]) : undefined
}

/** A test a run's results list as passed (`xcrew report --passed`), with the test bundle it ran in when the CLI names one. */
export type Passed = { test: string; target?: string }

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
  /** With `--passed`: the tests the run's results list as passed, `Suite/test`; absent when not asked for or unreadable. */
  passed?: Passed[]
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
  /** Read with a run's log: the scheme it names, which keys a backgrounded run whose log came late. */
  scheme?: string
}

/**
 * What `xcrew phase` says of a running MobileBuildMCP call: its log and phase; `outcome`, the log's verdict once printed,
 * and `quiet`, a log that stopped without one.
 */
export type Phase = { log?: string; phase?: string; scheme?: string; outcome?: boolean; quiet?: boolean }

/** One line of `xcrew doctor --problems --json`. */
export type Problem = { status: 'fail' | 'warn'; id: string; message: string }

/** A finished program's output, as the hooks module hands it back, with its exit status where the engine gave one. */
export type Ran = { stdout: string; stderr: string; exitCode?: number }

/**
 * How long the shim's answer is trusted before asking again, and a build that named nothing remembered: a development
 * checkout rebuilds when its sources change, and shows it within this. A freshness window, which stops no work; nothing
 * measured it.
 */
const RECHECK_MS = 30_000


export function shimPath(pluginRoot: string): string {
  return `${pluginRoot}/bin/xcrew`
}

/** A build the shim couldn't make: why, from what it wrote. */
export type FailedBuild = { failed: string }

/** The build to run while the shim's last answer is fresh, or why it failed; `ask` when it's stale or there is none. */
export function knownBuild(known: CliBuild | null, now: number): string | FailedBuild | undefined | 'ask' {
  if (!known || now < known.at || now - known.at >= RECHECK_MS) return 'ask'
  return known.path ?? (known.failed ? { failed: known.failed } : undefined)
}

/** Why the shim named no build: the first line of what it wrote that holds `error:`, as the compiler words one, else its last line. */
export function buildFailure(ran: Ran): string {
  const lines = ran.stderr.split('\n').map(line => line.trim()).filter(line => line !== '')
  const why = lines.find(line => line.includes('error:')) ?? lines.at(-1) ?? `the shim exited ${ran.exitCode ?? 'without a status'}`
  return `its CLI couldn't be built for this version: ${why}`
}

/** Only a path to a build counts: anything else on stdout leaves the CLI to the shim. */
export function namedBuild(stdout: string): string | null {
  const path = stdout.trim()
  return path.startsWith('/') && path.endsWith('/xcrew') ? path : null
}

export function reportArgs(server: string, kind: string, isError: boolean, repeated = false, passed = false): string[] {
  return ['report', '--server', server, '--kind', kind, ...(isError ? ['--error'] : []), ...(repeated ? ['--repeated'] : []), ...(passed ? ['--passed'] : [])]
}

export function phaseArgs(tool: string, launches: boolean, since: number, expectedTests: number | undefined, log: string | undefined): string[] {
  return ['phase', '--tool', tool, ...(launches ? ['--launches'] : []), '--since', String(since), ...(expectedTests === undefined ? [] : ['--expected', String(expectedTests)]), ...(log === undefined ? [] : ['--log', log])]
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

/** `xcrew doctor --text-and-problems`'s answer: the report and the band's problems from one run; nothing when it gave neither. */
export function textAndProblemsOf(answer: unknown): { text: string; problems: Problem[] } | undefined {
  const both = answer as { text?: unknown; problems?: unknown } | undefined
  return typeof both?.text === 'string' && Array.isArray(both.problems) ? { text: both.text, problems: both.problems as Problem[] } : undefined
}

/** Whether Tuist or XcodeGen generates this project; false when the CLI can't say, which leaves XcodeWrite allowed. */
export function isGeneratedOf(answer: unknown): boolean {
  return (answer as { isGenerated?: boolean } | undefined)?.isGenerated === true
}

/** Whether the project's generator reads YAML, as XcodeGen does; false when the CLI can't say. */
export function readsYamlOf(answer: unknown): boolean {
  return (answer as { readsYaml?: boolean } | undefined)?.readsYaml === true
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

/** The folders `xcrew gone` found aren't there any more; none when its answer can't be read. */
export function goneOf(answer: unknown): string[] {
  const gone = (answer ?? {}) as { gone?: unknown }
  return Array.isArray(gone.gone) ? gone.gone.filter((folder): folder is string => typeof folder === 'string') : []
}

/** The scheme selected in Xcode, as `xcrew project --xcode` answers. */
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

/** What `xcrew session` read of a session tool's text: its profiles, each a scheme and simulator, or the profile it names. */
export function sessionOf(answer: unknown): { profiles?: Record<string, { scheme?: string; simulatorName?: string }>; currentProfile?: string } | undefined {
  if (answer === null || typeof answer !== 'object') return undefined
  const { profiles, currentProfile } = answer as { profiles?: unknown; currentProfile?: unknown }
  const read: { profiles?: Record<string, { scheme?: string; simulatorName?: string }>; currentProfile?: string } = {}
  if (profiles !== null && typeof profiles === 'object') {
    read.profiles = Object.fromEntries(Object.entries(profiles as Record<string, unknown>).map(([name, profile]) => {
      const { scheme, simulatorName } = (profile ?? {}) as { scheme?: unknown; simulatorName?: unknown }
      return [name, { ...(typeof scheme === 'string' ? { scheme } : {}), ...(typeof simulatorName === 'string' ? { simulatorName } : {}) }]
    }))
  }
  if (typeof currentProfile === 'string') read.currentProfile = currentProfile
  return read
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

/** A file a generator writes: the manifest to edit instead, and the command that regenerates it. */
export type Generated = { manifest: string; generate: string }

/** The other worktrees whose run went meanwhile, as `xcrew runs --overlapped` answers; none when it couldn't say. */
export function overlappedOf(answer: unknown): string[] {
  return Array.isArray(answer) ? answer.filter((name): name is string => typeof name === 'string') : []
}

/** The manifest to edit instead of a generated file and the command that regenerates it, when `xcrew project --generated` named one. */
export function generatedOf(answer: unknown): Generated | undefined {
  const { manifest, generate } = (answer ?? {}) as { manifest?: unknown; generate?: unknown }
  return typeof manifest === 'string' && typeof generate === 'string' ? { manifest, generate } : undefined
}

/** Why a CLI command couldn't run. */
export function couldntRun(args: readonly string[], error: unknown): string {
  return `xcrew ${args.join(' ')} couldn't run: ${error instanceof Error ? error.message : String(error)}`
}

/** Whether a CLI command printed nothing and ended well, as `card --save` does: an answer of nothing, not a failure. */
export function endedQuietly(ran: Ran): boolean {
  return ran.stdout.trim() === '' && (ran.exitCode ?? 0) === 0
}

/** What a command printed, or, with nothing printed and an ending that wasn't quiet and well, how it ended. */
export function printedOr(args: readonly string[], ran: Ran, printed: string): string {
  return printed.trim() === '' && (ran.stderr.trim() !== '' || (ran.exitCode ?? 0) !== 0) ? readLine(args, ran) : printed.trimEnd()
}

/**
 * What's said of a CLI command that ran but gave no answer xcrew could read: the first line it wrote to standard error,
 * else its exit status, else that what it printed wasn't JSON.
 */
export function readLine(args: readonly string[], ran: Ran): string {
  return `xcrew ${args.join(' ')} gave no answer xcrew could read: ${unreadBecause(ran)}`
}

/** The options whose values name a moment or a run, which a read is the same read without. */
const PER_RUN_OPTIONS = ['--since', '--until', '--log', '--expected']

/** A read as one read whatever moments or run it names: its arguments without those options' values. */
export function readKey(read: string): string {
  return read.split(' ').filter((_, at, args) => !PER_RUN_OPTIONS.includes(args[at - 1] ?? '')).join(' ')
}

/** What the CLI writes to standard error before a line saying what it waits on, as `Progress.prefix` in the CLI. */
export const PROGRESS_PREFIX = 'xcrew progress: '

/** The lines in `text` that say what the CLI waits on, without their prefix. */
export function progressLines(text: string): string[] {
  return text.split('\n').filter(line => line.startsWith(PROGRESS_PREFIX)).map(line => line.slice(PROGRESS_PREFIX.length).trim())
}

function unreadBecause(ran: Ran): string {
  const said = ran.stderr.split('\n').map(line => line.trim()).find(line => line !== '' && !line.startsWith(PROGRESS_PREFIX.trim()))
  if (said !== undefined) return said
  if (ran.exitCode !== undefined && ran.exitCode !== 0) return `it exited ${ran.exitCode}${ran.stdout.trim() === '' ? ', writing nothing' : ''}`
  return 'it printed something other than JSON'
}
