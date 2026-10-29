import { atom, read, update } from 'claude-code'
import type { EngineInterface } from 'claude-code'
import type { CliBuild, FailureList } from '../../types'

/**
 * The mod's one way to the Swift CLI, which reads and parses everything the servers print. The mod
 * hands it text and gets JSON back; see the mod's rule in docs/architecture.md.
 */

/** One failing test or compile error, for the failure pane; the state contract declares its shape. */
export type Failure = FailureList['items'][number]

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
}

/** What `xcrew phase` says of a running MobileBuildMCP call. */
export type Phase = { log?: string; phase?: string }

/** One line of `xcrew doctor --problems --json`. */
export type Problem = { status: 'fail' | 'warn'; id: string; message: string }

/** How long the shim's answer is trusted before asking again: a development checkout rebuilds when its sources change. */
const RECHECK_MS = 30_000
/** The shim's last answer, for the session: the build to run, or none. */
const buildState = atom({ plugin: 'xcrew', key: 'build' } as const, null as CliBuild | null)
/** The question in flight, which callers at the same moment share rather than each starting a shim. */
let asking: Promise<string | undefined> | undefined

function shim($: EngineInterface): string {
  return `${$.plugin.root}/bin/xcrew`
}

/** Starts a program of the CLI's: the mod's one process. */
function start($: EngineInterface, program: string, args: string[], timeoutMs: number, stdin?: string) {
  return $.process.run([program, ...args], { timeoutMs, env: { XCREW_ROOT: $.plugin.root }, ...(stdin === undefined ? {} : { stdin }) })
}

/**
 * The build the shim runs, asked for at most every 30 s, within the caller's own time: when the
 * shim must first build, a caller with ten seconds doesn't wait two minutes.
 */
async function build($: EngineInterface, timeoutMs: number): Promise<string | undefined> {
  const now = await $.clock.now()
  const known = await read($, buildState)
  if (known && now >= known.at && now - known.at < RECHECK_MS) return known.path ?? undefined
  asking ??= start($, shim($), ['--binary-path'], timeoutMs)
    .then(async ran => {
      const path = ran.stdout.trim()
      // Only a path to a build counts: anything else on stdout leaves the CLI to the shim.
      const named = path.startsWith('/') && path.endsWith('/xcrew') ? path : null
      await update($, buildState, () => ({ path: named, at: now }))
      return named ?? undefined
    })
    .finally(() => {
      asking = undefined
    })
  return asking
}

/**
 * Runs the CLI. The shim's own work is several times the build's, and the band asks once a second,
 * so the build it names runs directly. When the build can't be started, the shim runs instead; a
 * command that ran out of time isn't started again, which would double the wait.
 */
async function xcrew($: EngineInterface, args: string[], timeoutMs: number, stdin?: string) {
  const binary = await build($, timeoutMs).catch(() => undefined)
  if (binary) {
    const startedAt = await $.clock.now()
    try {
      return await start($, binary, args, timeoutMs, stdin)
    } catch (error) {
      if ((await $.clock.now()) - startedAt >= timeoutMs) throw error
      await update($, buildState, () => null)
    }
  }
  return start($, shim($), args, timeoutMs, stdin)
}

async function run($: EngineInterface, args: string[], stdin?: string, timeoutMs = 60_000): Promise<unknown> {
  return JSON.parse((await xcrew($, args, timeoutMs, stdin)).stdout)
}

/** The report for a finished call; without one, the outcome is whether the server reported an error. */
export async function report($: EngineInterface, server: string, kind: string, text: string, isError: boolean): Promise<Report> {
  const answer = await run($, ['report', '--server', server, '--kind', kind, ...(isError ? ['--error'] : [])], text, 120_000).catch(() => undefined)
  const parsed = (answer ?? {}) as Partial<Report>
  return { ...parsed, ok: parsed.ok ?? !isError, failures: parsed.failures ?? [], notes: parsed.notes ?? [] }
}

/** The running call's log, once it appears, and the phase read from it. */
export async function phase($: EngineInterface, tool: string, since: number, expectedTests: number | undefined, log: string | undefined): Promise<Phase> {
  const args = ['phase', '--tool', tool, '--since', String(since), ...(expectedTests === undefined ? [] : ['--expected', String(expectedTests)]), ...(log === undefined ? [] : ['--log', log])]
  return ((await run($, args, undefined, 10_000).catch(() => undefined)) as Phase | undefined) ?? {}
}

/** What `xcrew doctor` finds wrong, worst first; nothing outside an Apple-platform project. */
export async function problems($: EngineInterface): Promise<Problem[]> {
  return ((await run($, ['doctor', '--problems', '--json']).catch(() => undefined)) as Problem[] | undefined) ?? []
}


/** A CLI command's own text, for `/xcrew doctor`, or why it couldn't run. */
export async function text($: EngineInterface, args: string[]): Promise<string> {
  return xcrew($, args, 120_000).then(
    ran => `${ran.stdout}${ran.stderr}`.trimEnd(),
    error => `xcrew ${args.join(' ')} couldn't run: ${error instanceof Error ? error.message : String(error)}`,
  )
}

/** Whether Tuist or XcodeGen generates this project; false when the CLI can't say, which leaves XcodeWrite allowed. */
export async function isGeneratedProject($: EngineInterface): Promise<boolean> {
  const answer = (await run($, ['project'], undefined, 10_000).catch(() => undefined)) as { isGenerated?: boolean } | undefined
  return answer?.isGenerated === true
}
