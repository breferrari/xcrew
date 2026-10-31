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
type ProjectAnswer = { isGenerated: boolean; setup?: string; scheme?: string; activeProfile?: string; xcodeState?: string; xcodeScheme?: string; followsXcode?: boolean; xcodeHostsServer?: boolean; generate?: string; app?: string; root?: string; branch?: string; commit?: string; manifest?: string }

/** One call the mod made to the Swift CLI: its arguments, what it piped in, and the program when it wasn't the shim. */
export type CliCall = { args: readonly string[]; stdin?: string; program?: string; timeoutMs?: number }

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
    /** What `xcrew runs` answers each time: the other worktrees' runs, or the Error it fails with. */
    runs?: () => unknown
    noBuild?: boolean
    build?: { fails: 'to start' } | { fails: 'by timing out'; clock: { advance: (ms: number) => Promise<void> } }
  } = {},
): CliCall[] {
  const calls: CliCall[] = []
  const reports = [...(answers.reports ?? [])]
  on('process.run', async (_, e) => {
    const args = e.argv.slice(1)
    const program = e.argv[0] ?? ''
    const timeoutMs = e.init?.timeoutMs
    calls.push({ args, ...(e.init?.stdin === undefined ? {} : { stdin: e.init.stdin }), ...(program.endsWith('/bin/xcrew') ? {} : { program }), ...(timeoutMs === undefined ? {} : { timeoutMs }) })
    if (args[0] === 'doctor' && answers.doctorFails?.()) throw new Error('timed out')
    if (args[0] === 'report' && answers.reportFails?.()) throw new Error('timed out')
    const runs = args[0] === 'runs' ? answers.runs?.() : undefined
    if (runs instanceof Error) throw runs
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
      : args[0] === 'doctor' ? (answers.problems ?? [])
      : args[0] === 'project' ? ((typeof answers.project === 'function' ? answers.project(args) : answers.project) ?? { isGenerated: false })
      : args[0] === 'affected' ? (answers.affected?.(args) ?? null)
      : args[0] === 'setup' ? (answers.setup?.(args) ?? null)
      : args[0] === 'note' ? { notes: answers.notes?.(args, e.init?.stdin) ?? [] }
      : args[0] === 'runs' ? (runs ?? [])
      : null
    )
    const stdout = args[0] === '--binary-path' ? (answers.noBuild ? '' : `${BUILT_BINARY}\n`) : (printed ?? JSON.stringify(answer))
    return { value: { exitCode: 0, stdout, stderr, isStdoutTruncated: false, isStderrTruncated: false } }
  })
  return calls
}
