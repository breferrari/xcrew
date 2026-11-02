import type { Engine } from 'claude-code/testing'
import type { On, ToolCallArgs, ToolCallResult } from 'claude-code'
import type { Phase, Problem, Report } from './cli'

/** The store as a plain map, holding `stored` at first, so a test reads what the mod kept. */
export function mapStore(on: On, stored: Record<string, unknown> = {}): Map<string, unknown> {
  const store = new Map<string, unknown>(Object.entries(stored))
  on('store.get', (_, e) => ({ value: store.get(e.key) }))
  on('store.set', (_, e) => {
    store.set(e.key, e.value)
    return { value: undefined }
  })
  on('store.keys', () => ({ value: [...store.keys()] }))
  on('store.delete', (_, e) => {
    store.delete(e.key)
    return { value: undefined }
  })
  return store
}

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

/** The person typing `text` at the prompt and pressing return. */
export function submitPrompt($: Engine, text: string) {
  return $.prompt.submit({ text, wait: false, origin: { kind: 'composer' } })
}

/** What `xcrew project` answers: with `--profiles`, the line offering setup when MobileBuildMCP has no scheme to build with; with `--manifest`, the command that regenerates the project when the file is a manifest. */
type ProjectAnswer = { isGenerated: boolean; readsYaml?: boolean; setup?: string; scheme?: string; activeProfile?: string; xcodeState?: string; xcodeScheme?: string; followsXcode?: boolean; xcodeHostsServer?: boolean; generate?: string; app?: string; root?: string; branch?: string; commit?: string; manifest?: string }

/** One call the mod made to the Swift CLI: its arguments, what it piped in, and the program when it wasn't the shim. */
/** A CLI call a stub answered: its arguments, what was piped in, the program when not the shim, its time limit, and whether it was spawned rather than run. */
export type CliCall = { args: readonly string[]; stdin?: string; program?: string; timeoutMs?: number; spawned?: true }

/**
 * Answers every `$.process.spawn`: a spawn of `--binary-path` names `BUILT_BINARY`, after `held` when given; `fails`
 * makes it unable to start, and `printsNothing` ends it with nothing on standard output, as a killed or failed build
 * does. Each is recorded in `calls`, marked `spawned`.
 */
export function stubSpawn(on: On, calls: CliCall[] = [], { held, fails, printsNothing }: { held?: Promise<void>; fails?: boolean; printsNothing?: boolean } = {}): CliCall[] {
  on('process.spawn', async function* (_, e) {
    calls.push({ args: e.argv.slice(1), spawned: true })
    if (fails) throw new Error('spawn ENOENT')
    if (held) await held
    if (e.argv.includes('--binary-path') && !printsNothing) yield { stream: 'stdout' as const, text: `${BUILT_BINARY}\n` }
    return { value: { code: 0, signal: null } }
  })
  return calls
}

/** Where the stand-in shim says its build is, for `--binary-path`. */
export const BUILT_BINARY = '/cache/0123456789abcdef/xcrew'

/**
 * Stands for the Swift CLI, which does the reading the mod hands off: each `report` answers with
 * the next of `reports` (the last one repeats), `phase` with what `phase` returns for its
 * arguments, `doctor` with `problems`, and `project` with `project`. `build` is how the build
 * itself behaves when the mod runs it directly: answers, can't be started, or runs past its time.
 */
export function stubCli(
  on: On,
  answers: {
    reports?: Partial<Report>[]
    phase?: (args: readonly string[]) => Phase
    problems?: Problem[]
    /** The doctor can't run: the shim is building, or it timed out. */
    doctorFails?: () => boolean
    /** The report can't be read: the CLI timed out, or the shim couldn't build. */
    reportFails?: () => boolean
    /** A function may answer later, as a CLI that takes its time does. */
    project?: ProjectAnswer | ((args: readonly string[]) => ProjectAnswer | Promise<ProjectAnswer>)
    /** What `xcrew note` answers, for its arguments and what the mod pipes in. */
    notes?: (args: readonly string[], stdin: string | undefined) => string[]
    /** What `xcrew setup --choices` answers as JSON, or what a plain `xcrew setup` prints, for its arguments. */
    setup?: (args: readonly string[]) => unknown
    /** What `xcrew affected` answers, for its arguments. */
    affected?: (args: readonly string[]) => unknown
    /** The text `xcrew look` prints, for its arguments, or the Error it fails with. */
    look?: (args: readonly string[]) => string | Error
    /** What `xcrew evidence` prints, for what the mod sends it, with what it writes to stderr, or the Error it fails with. */
    evidence?: (stdin: string | undefined) => string | Error | { stdout: string; stderr: string }
    /** What `xcrew session` answers for a session tool's text the mod pipes in. */
    session?: (stdin: string | undefined) => unknown
    /** What `xcrew runs` answers each time: the other worktrees' runs, or the Error it fails with. */
    runs?: () => unknown
    /** What `xcrew runs --overlapped` answers, for its arguments: the worktrees whose run went meanwhile, a promise of them that answers later, or the Error it fails with. */
    overlapped?: (args: readonly string[]) => unknown
    /** What `xcrew flaky` answers for the marks and repeated run the mod pipes in: the marks after the run. */
    flaky?: (stdin: string | undefined) => unknown
    /** What `xcrew gone` answers for the folders it's asked about, or the Error it fails with. */
    gone?: (folders: readonly string[]) => unknown
    noBuild?: boolean
    build?: { fails: 'to start' } | { fails: 'by timing out'; clock: { advance: (ms: number) => Promise<void> } }
    /** How the session start's background build goes: held until a promise settles, or unable to start. */
    spawn?: { held?: Promise<void>; fails?: boolean; printsNothing?: boolean }
  } = {},
): CliCall[] {
  const calls: CliCall[] = []
  stubSpawn(on, calls, answers.spawn)
  const reports = [...(answers.reports ?? [])]
  on('process.run', async (_, e) => {
    const args = e.argv.slice(1)
    const program = e.argv[0] ?? ''
    const timeoutMs = e.init?.timeoutMs
    calls.push({ args, ...(e.init?.stdin === undefined ? {} : { stdin: e.init.stdin }), ...(program.endsWith('/bin/xcrew') ? {} : { program }), ...(timeoutMs === undefined ? {} : { timeoutMs }) })
    if (args[0] === 'doctor' && answers.doctorFails?.()) throw new Error('timed out')
    if (args[0] === 'report' && answers.reportFails?.()) throw new Error('timed out')
    const asksOverlap = args[0] === 'runs' && args.includes('--overlapped')
    const runs = args[0] === 'runs' && !asksOverlap ? answers.runs?.() : undefined
    if (runs instanceof Error) throw runs
    const overlapped = asksOverlap ? await answers.overlapped?.(args) : undefined
    if (overlapped instanceof Error) throw overlapped
    const gone = args[0] === 'gone' ? answers.gone?.(args.slice(1)) : undefined
    if (gone instanceof Error) throw gone
    // The commands that print text rather than JSON.
    const printing = new Map<string, () => string | Error | { stdout: string; stderr: string } | undefined>([['look', () => answers.look?.(args)], ['evidence', () => answers.evidence?.(e.init?.stdin)]])
    if (args[0] === 'setup' && !args.includes('--choices')) printing.set('setup', () => String(answers.setup?.(args) ?? ''))
    const answered = args[0] === undefined ? undefined : printing.has(args[0]) ? (printing.get(args[0])?.() ?? '') : undefined
    if (answered instanceof Error) throw answered
    const printed = typeof answered === 'object' ? answered.stdout : answered
    const stderr = typeof answered === 'object' ? answered.stderr : ''
    if (program === BUILT_BINARY && answers.build) {
      if (answers.build.fails === 'by timing out') await answers.build.clock.advance(timeoutMs ?? 30_000)
      throw new Error(answers.build.fails === 'to start' ? 'spawn ENOENT' : 'timed out')
    }
    const answer = await (
      args[0] === 'report' ? ((reports.length > 1 ? reports.shift() : reports[0]) ?? {})
      : args[0] === 'phase' ? (answers.phase?.(args) ?? {})
      : args[0] === 'doctor' ? (args.includes('--text-and-problems') ? { text: 'the doctor\'s report', problems: answers.problems ?? [] } : (answers.problems ?? []))
      : args[0] === 'project' ? ((typeof answers.project === 'function' ? answers.project(args) : answers.project) ?? { isGenerated: false })
      : args[0] === 'affected' ? (answers.affected?.(args) ?? null)
      : args[0] === 'setup' ? (answers.setup?.(args) ?? null)
      : args[0] === 'note' ? { notes: answers.notes?.(args, e.init?.stdin) ?? [] }
      : asksOverlap ? (overlapped ?? [])
      : args[0] === 'runs' ? (runs ?? [])
      : args[0] === 'flaky' ? (answers.flaky?.(e.init?.stdin) ?? null)
      : args[0] === 'session' ? (answers.session?.(e.init?.stdin) ?? {})
      : args[0] === 'gone' ? (gone ?? null)
      : null
    )
    const stdout = args[0] === '--binary-path' ? (answers.noBuild ? '' : `${BUILT_BINARY}\n`) : (printed ?? JSON.stringify(answer))
    return { value: { exitCode: 0, stdout, stderr, isStdoutTruncated: false, isStderrTruncated: false } }
  })
  return calls
}
