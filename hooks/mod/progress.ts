import type { EngineInterface } from 'claude-code'

/**
 * What a MobileBuildMCP run is doing now, read from the xcodebuild output it logs as the run goes.
 * Test results land in batches as the parallel runners flush, so a test count moves in steps.
 */

/** The task line's module: `… (in target 'Utility' from project 'Foundation')`. */
const TASK = /^(\S+) (.*)\(in target '([^']+)' from project/
const TEST_CASE = /^Test case '.*' (?:passed|failed)/gm

/** A short phase for the band, or undefined before the first task. `expectedTests` is the last run's total. */
export function phaseOf(log: string, expectedTests?: number): string | undefined {
  const testing = log.lastIndexOf('\nTesting started')
  if (testing !== -1 || log.startsWith('Testing started')) {
    const done = (log.slice(Math.max(testing, 0)).match(TEST_CASE) ?? []).length
    return expectedTests !== undefined && done <= expectedTests ? `testing ${done} of ${expectedTests}` : `testing · ${done} done`
  }
  const lines = log.split('\n')
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    const task = TASK.exec(lines[index] ?? '')
    if (!task) continue
    const [, kind, rest = '', target] = task
    // The file changes too fast to read and makes the line too long; the module is what says where the build is.
    if (kind === 'SwiftCompile' && /\.swift /.test(rest)) return `compiling ${target}`
    if (kind === 'Ld' || kind === 'Libtool') return `linking ${target}`
    if (kind === 'CodeSign') return `signing ${target}`
    return `building ${target}`
  }
  return undefined
}

/**
 * The log of the MobileBuildMCP run that started at `since`: the newest `<tool>_…log` written
 * since then, in this project's workspace folder (`<project folder name>-<hash>`).
 */
export async function findRunLog($: EngineInterface, tool: string, since: number): Promise<string | undefined> {
  const home = await $.env.get('HOME')
  const root = await $.session.root()
  if (!home || !root) return undefined
  const workspaces = `${home}/Library/Developer/MobileBuildMCP/workspaces`
  const project = root.slice(root.lastIndexOf('/') + 1)
  const folders = (await $.fs.list(workspaces)).filter(entry => entry.kind === 'dir' && entry.name.startsWith(`${project}-`))
  let newest: { path: string; mtime: number } | undefined
  for (const folder of folders) {
    const logs = `${workspaces}/${folder.name}/logs`
    const entries = await $.fs.list(logs).catch(() => [])
    for (const entry of entries) {
      const isRunLog = entry.kind === 'file' && entry.name.startsWith(`${tool}_`) && !entry.name.includes('parser-debug')
      if (isRunLog && entry.mtimeMs >= since && entry.mtimeMs > (newest?.mtime ?? -1)) newest = { path: `${logs}/${entry.name}`, mtime: entry.mtimeMs }
    }
  }
  return newest?.path
}
