import type { EngineInterface } from 'claude-code'
import type { FailureList } from '../../types'

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

/** Runs `bin/xcrew` with these arguments: the mod's one process. */
function xcrew($: EngineInterface, args: string[], timeoutMs: number, stdin?: string) {
  return $.process.run([`${$.plugin.root}/bin/xcrew`, ...args], { timeoutMs, ...(stdin === undefined ? {} : { stdin }) })
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
