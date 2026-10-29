import { average, stopwatch } from './format'
import { DURATIONS_PREFIX, HISTORY } from './timing'

export const USAGE = [
  '/xcrew doctor   check this Mac and project, with the fix for anything wrong',
  '/xcrew history  how long each build, test and app run usually takes',
  '/xcrew failures every failing test and compile error from the last failing run, in a pane',
  '/xcrew close    close that pane',
].join('\n')

/** `/xcrew`, answered by the mod itself: nothing reaches Claude, and nothing costs a turn. */
export const COMMAND = { name: 'xcrew', description: 'Xcrew: doctor, history, failures or close', argumentHint: '[doctor|history|failures|close]' }

/** `/xcrew history`: each tool's usual duration, slowest first, from its stored runs. */
export function historyText(stored: { key: string; runs: number[] | undefined }[]): string {
  const rows = stored.map(({ key, runs }) => ({ tool: key.slice(DURATIONS_PREFIX.length), runs: runs ?? [] }))
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
