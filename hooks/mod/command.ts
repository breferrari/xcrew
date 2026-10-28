import type { EngineInterface, On } from 'claude-code'
import { average, stopwatch } from './format'
import { DURATIONS_PREFIX, HISTORY } from './timing'

const USAGE = [
  '/xcrew doctor   check this Mac and project, with the fix for anything wrong',
  '/xcrew repair   re-copy macro plugins macOS killed at launch',
  '/xcrew history  how long each build, test and app run usually takes',
].join('\n')

/** Subcommands that run the CLI: the person's word, then the CLI's. */
const CLI_SUBCOMMANDS: Record<string, string> = { doctor: 'doctor', repair: 'repair-macros' }

/** `/xcrew`, answered by the mod itself: nothing reaches Claude, and nothing costs a turn. */
export function registerCommand(on: On): void {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await $.command.register({ name: 'xcrew', description: 'Xcrew: doctor, repair or history', argumentHint: '[doctor|repair|history]' })
    return started
  })

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
  const width = Math.max(...timed.map(row => row.tool.length))
  // Claude Code puts the plugin's name before the first line; a heading keeps the rows aligned.
  const heading = `usual durations, over the last ${HISTORY} runs of each tool`
  const lines = timed.map(({ tool, runs }) => {
    const count = `${runs.length} ${runs.length === 1 ? 'run' : 'runs'}`
    return `${tool.padEnd(width)}  avg ${stopwatch(average(runs))} · last ${stopwatch(runs.at(-1) ?? 0)} · ${count}`
  })
  return [heading, ...lines].join('\n')
}
