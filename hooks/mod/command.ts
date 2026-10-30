import { average, stopwatch } from './format'
import { HISTORY, isStale } from './timing'

export const USAGE = [
  '/xcrew doctor   check this Mac and project, with the fix for anything wrong',
  '/xcrew history  how long each build, test and app run usually takes',
  '/xcrew ledger   the tests seen failing and then passing on this branch, for a pull request',
  '/xcrew failures every failing test and compile error from the last failing run, in a pane',
  '/xcrew close    close that pane',
].join('\n')

/** `/xcrew`, answered by the mod itself: nothing reaches Claude, and nothing costs a turn. */
export const COMMAND = { name: 'xcrew', description: 'Xcrew: doctor, history, ledger, failures or close', argumentHint: '[doctor|history|ledger|failures|close]' }

/** Which history lines a look keeps: those a run updated within `HISTORY_KEPT_MS`; an undated one is dated now. */
export function keptHistory(tools: string[], updated: Readonly<Record<string, unknown>>, now: number): { kept: string[]; stamp: string[]; gone: string[] } {
  const sorted = { kept: [] as string[], stamp: [] as string[], gone: [] as string[] }
  for (const tool of tools) {
    if (typeof updated[tool] !== 'number') sorted.stamp.push(tool)
    if (isStale(updated[tool], now)) sorted.gone.push(tool)
    else sorted.kept.push(tool)
  }
  return sorted
}

/** `/xcrew history`: each tool's usual duration, slowest first, from its stored runs. */
export function historyText(stored: { tool: string; runs: number[] | undefined }[]): string {
  const rows = stored.map(({ tool, runs }) => ({ tool, runs: runs ?? [] }))
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
