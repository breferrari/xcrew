import { average, stopwatch } from './format'
import { HISTORY, isStale } from './timing'

export const USAGE = [
  '/xcrew doctor   check this Mac and project, with the fix for anything wrong',
  '/xcrew xcode    which Xcode is which: those installed, the selected one, the project\'s pin, CI\'s, and the one open',
  '/xcrew history  how long each build, test and app run usually takes',
  '/xcrew ledger   the tests seen failing and then passing on this branch, for a pull request',
  '/xcrew evidence this branch\'s evidence for a pull request, then the images to attach',
  '/xcrew failures every failing test and compile error from the last failing run, in a pane',
  '/xcrew close    close that pane',
].join('\n')

/** `/xcrew`, answered by the mod itself: nothing reaches Claude, and nothing costs a turn. */
export const COMMAND = { name: 'xcrew', description: 'Xcrew: doctor, xcode, history, ledger, evidence, failures or close', argumentHint: '[doctor|xcode|history|ledger|evidence|failures|close]' }

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

/** `/xcrew history`: each tool's usual duration, slowest first, from its passing runs, and its failed runs apart. */
export function historyText(stored: { tool: string; runs: number[] | undefined; failed?: number[] }[]): string {
  const rows = stored.map(({ tool, runs, failed }) => ({ tool, runs: runs ?? [], failed: failed ?? [] }))
  const timed = rows.filter(row => row.runs.length > 0 || row.failed.length > 0).sort((a, b) => (b.runs.length > 0 ? average(b.runs) : 0) - (a.runs.length > 0 ? average(a.runs) : 0))
  if (timed.length === 0) return 'No builds or test runs timed yet.'
  // Claude Code puts the plugin's name before the first line; a heading keeps the rows aligned.
  const heading = `usual durations, over the last ${HISTORY} runs of each tool`
  // Numbers first: a long scheme and test selection then can't push them out of line.
  const stats = timed.map(({ runs, failed }) => {
    const failures = failed.length > 0 ? ` · ${failed.length} failed ${failed.length === 1 ? 'run' : 'runs'}, ${stopwatch(average(failed))}` : ''
    const passing = runs.length > 0 ? `avg ${stopwatch(average(runs))} · last ${stopwatch(runs.at(-1) ?? 0)} · ${runs.length} ${runs.length === 1 ? 'run' : 'runs'}` : 'no passing run yet'
    return `${passing}${failures}`
  })
  const width = Math.max(...stats.map(stat => stat.length))
  const lines = timed.map(({ tool }, index) => `${(stats[index] ?? '').padEnd(width)}  ${tool}`)
  return [heading, ...lines].join('\n')
}
