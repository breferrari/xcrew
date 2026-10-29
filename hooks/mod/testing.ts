import type { Engine } from 'claude-code/testing'
import type { On, ToolCallArgs, ToolCallResult } from 'claude-code'
import type { Phase, Problem, Report } from './cli'

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

/** One call the mod made to the Swift CLI: its arguments after `bin/xcrew`, and what it piped in. */
export type CliCall = { args: readonly string[]; stdin?: string }

/**
 * Stands for the Swift CLI, which does the reading the mod hands off: each `report` answers with
 * the next of `reports` (the last one repeats), `phase` with what `phase` returns for its
 * arguments, and `doctor` with `problems`.
 */
export function stubCli(
  on: On,
  answers: { reports?: Partial<Report>[]; phase?: (args: readonly string[]) => Phase; problems?: Problem[] } = {},
): CliCall[] {
  const calls: CliCall[] = []
  const reports = [...(answers.reports ?? [])]
  on('process.run', (_, e) => {
    const args = e.argv.slice(1)
    calls.push({ args, ...(e.init?.stdin === undefined ? {} : { stdin: e.init.stdin }) })
    const answer =
      args[0] === 'report' ? ((reports.length > 1 ? reports.shift() : reports[0]) ?? {})
      : args[0] === 'phase' ? (answers.phase?.(args) ?? {})
      : args[0] === 'doctor' ? (answers.problems ?? [])
      : null
    return { value: { exitCode: 0, stdout: JSON.stringify(answer), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  return calls
}
