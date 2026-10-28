import type { EngineInterface, On } from 'claude-code'
import { average, stopwatch } from './format'
import { DURATIONS_PREFIX, HISTORY } from './timing'
import { closeFailures, openFailures } from './failures'

const USAGE = [
  '/xcrew doctor   check this Mac and project, with the fix for anything wrong',
  '/xcrew history  how long each build, test and app run usually takes',
  '/xcrew failures every failing test and compile error from the last failing run, in a pane',
  '/xcrew close    close that pane',
].join('\n')

/** Subcommands that run the CLI: the person's word, then the CLI's. */
const CLI_SUBCOMMANDS: Record<string, string> = { doctor: 'doctor' }

export const COMMAND = { name: 'xcrew', description: 'Xcrew: doctor, history, failures or close', argumentHint: '[doctor|history|failures|close]' }

/** `/xcrew`, answered by the mod itself: nothing reaches Claude, and nothing costs a turn. */
export function registerCommand(on: On): void {
  on('command.run', { command: 'xcrew' }, async ($, e) => {
    const subcommand = (e.args ?? '').trim()
    const cli = CLI_SUBCOMMANDS[subcommand]
    if (cli) {
      const output = await $.process.run([`${$.plugin.root}/bin/xcrew`, cli], { timeoutMs: 120_000 }).then(
        ran => `${ran.stdout}${ran.stderr}`.trimEnd(),
        error => `xcrew ${cli} couldn't run: ${error instanceof Error ? error.message : String(error)}`,
      )
      return { text: output }
    }
    if (subcommand === 'history') return { text: await history($) }
    if (subcommand === 'failures') return { text: await openFailures($) }
    if (subcommand === 'close') return { text: await closeFailures($) }
    return { text: USAGE }
  })
}

async function history($: EngineInterface): Promise<string> {
  const keys = (await $.store.keys()).filter(key => key.startsWith(DURATIONS_PREFIX))
  const rows = await Promise.all(
    keys.map(async key => ({ tool: key.slice(DURATIONS_PREFIX.length), runs: ((await $.store.get(key)) as number[] | undefined) ?? [] })),
  )
  const timed = rows.filter(row => row.runs.length > 0).sort((a, b) => average(b.runs) - average(a.runs))
  if (timed.length === 0) return 'No builds or test runs timed yet.'
  // Claude Code puts the plugin's name before the first line; a heading keeps the rows aligned.
  const heading = `usual durations, over the last ${HISTORY} runs of each tool`
  // Numbers first: a long scheme and test selection then can't push them out of line.
  const stats = timed.map(({ runs }) => `avg ${stopwatch(average(runs))} · last ${stopwatch(runs.at(-1) ?? 0)} · ${runs.length} ${runs.length === 1 ? 'run' : 'runs'}`)
  const width = Math.max(...stats.map(stat => stat.length))
  const lines = timed.map(({ tool }, index) => `${(stats[index] ?? '').padEnd(width)}  ${tool}`)
  return [heading, ...lines].join('\n')
}
