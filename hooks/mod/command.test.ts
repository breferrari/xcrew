import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'
import { historyKey, scopeKey, updatedKey } from './timing'
import { callTool, runCommand, withoutIfBuilt } from './testing'

/** Stands for the engine: registers commands, and answers `bin/xcrew` with `outputs[subcommand]`. */
function engine(on: On, outputs: Record<string, string> = {}) {
  const registered: string[] = []
  const runs: (readonly string[])[] = []
  on('command.register', (_, e) => {
    registered.push(e.name)
    return { value: { command: e.name } }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('process.run', (_, e) => {
    // The shim's `--if-built` runs the build that's there; a command's run is the same with or without it.
    const argv = withoutIfBuilt(e.argv)
    // The session start's own look for problems, and its read of Xcode's selection, aren't a command's run.
    if (!argv.includes('--problems') && !argv.includes('--xcode')) runs.push(argv)
    return { value: { exitCode: 0, stdout: outputs[argv[1] ?? ''] ?? '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  return { registered, runs }
}

async function start($: Engine) {
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
}

test('the session offers /xcrew', async ($, on) => {
  mock.store(on)
  const seen = engine(on)
  await start($)
  expect(seen.registered).toEqual(['xcrew'])
})

test('/xcrew doctor names its session, so the doctor checks the session it runs in', async ($, on) => {
  mock.store(on)
  const seen = engine(on, { doctor: JSON.stringify({ text: 'ok    xcrew/briefing-current  the running xcrew\'s', problems: [] }) })
  on('session.id', () => ({ value: '5f0c1a2b-0000-4000-8000-000000000004' }))
  await start($)
  await runCommand($, 'xcrew', 'doctor')
  expect(seen.runs.map(argv => argv.slice(1))).toEqual([['doctor', '--text-and-problems', '--session', '5f0c1a2b-0000-4000-8000-000000000004']])
})

test('/xcrew doctor shows the doctor\'s report without a turn for Claude', async ($, on) => {
  mock.store(on)
  const seen = engine(on, { doctor: JSON.stringify({ text: 'ok    xcode-mcp/headless-enabled  enabled\nwarn  xcode/pin  Xcode 26.4 is not installed', problems: [] }) })
  await start($)

  const ran = await runCommand($, 'xcrew', 'doctor')

  // One run of the checks gives both the report and the band's problems.
  expect(seen.runs.map(argv => argv.slice(1))).toEqual([['doctor', '--text-and-problems']])
  expect(seen.runs[0]?.[0]).toMatch(/\/bin\/xcrew$/)
  expect(ran.text).toContain('warn  xcode/pin')
  expect(ran.context).toBeUndefined()
})

test('/xcrew history lists each tool\'s usual duration, slowest first', async ($, on) => {
  mock.store(on, {
    [historyKey(scopeKey('', 'build_sim'))]: [60_000, 80_000],
    [historyKey(scopeKey('', 'RunAllTests'))]: [300_000],
    'other.key': 1,
  })
  engine(on)
  await start($)

  const ran = await runCommand($, 'xcrew', 'history')

  expect(ran.text).toBe('usual durations, over the last 10 runs of each tool\navg 5:00 · last 5:00 · 1 run   RunAllTests\navg 1:10 · last 1:20 · 2 runs  build_sim')
})

const DAY = 24 * 60 * 60_000

test('/xcrew history drops a line no run has updated for two weeks', async ($, on) => {
  const clock = mock.clock(on)
  const now = clock.now()
  mock.store(on, {
    [historyKey(scopeKey('', 'test_sim · › AppTests'))]: [60_000],
    [updatedKey(scopeKey('', 'test_sim · › AppTests'))]: now - 15 * DAY,
    [historyKey(scopeKey('', 'test_sim › AppTests'))]: [50_000],
    [updatedKey(scopeKey('', 'test_sim › AppTests'))]: now - DAY,
  })
  engine(on)
  await start($)
  await clock.settle()

  const ran = await runCommand($, 'xcrew', 'history')

  expect(ran.text).toBe('usual durations, over the last 10 runs of each tool\navg 0:50 · last 0:50 · 1 run  test_sim › AppTests')
})

/** A month-old run says nothing about today's build: it mustn't count toward the usual time, or come back. */
test('a run two weeks after its line was last updated starts the line afresh', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on, { [historyKey(scopeKey('', 'BuildProject'))]: [600_000, 600_000], [updatedKey(scopeKey('', 'BuildProject'))]: clock.now() - 15 * DAY })
  engine(on)
  on('tool.call', async () => {
    await clock.advance(30_000)
    return { result: {}, text: 'built' }
  })
  await start($)
  await callTool($, 'mcp__xcode__BuildProject')

  expect((await runCommand($, 'xcrew', 'history')).text).toContain('avg 0:30 · last 0:30 · 1 run  BuildProject')
})

test('/xcrew history keeps an undated line for two weeks from the first look', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on, { [historyKey(scopeKey('', 'build_sim'))]: [60_000] })
  engine(on)
  await start($)

  expect((await runCommand($, 'xcrew', 'history')).text).toContain('build_sim')
  await clock.advance(13 * DAY)
  expect((await runCommand($, 'xcrew', 'history')).text).toContain('build_sim')
  await clock.advance(2 * DAY)
  expect((await runCommand($, 'xcrew', 'history')).text).toBe('No builds or test runs timed yet.')
})

test('/xcrew history with nothing timed yet says so', async ($, on) => {
  mock.store(on)
  engine(on)
  await start($)
  const ran = await runCommand($, 'xcrew', 'history')
  expect(ran.text).toBe('No builds or test runs timed yet.')
})

test('/xcrew xcode shows which Xcode is which, from the CLI', async ($, on) => {
  mock.store(on)
  const seen = engine(on, { xcode: 'selected  Xcode 27.2, at /Applications/Xcode.app\n' })
  await start($)
  const ran = await runCommand($, 'xcrew', 'xcode')
  expect(seen.runs.map(argv => argv.slice(1))).toEqual([['xcode']])
  expect(ran.text).toBe('selected  Xcode 27.2, at /Applications/Xcode.app')
})

test('/xcrew alone lists what it can do', async ($, on) => {
  mock.store(on)
  const seen = engine(on)
  await start($)
  const ran = await runCommand($, 'xcrew')
  expect(ran.text).toMatch(/doctor[\s\S]*history[\s\S]*ledger[\s\S]*flaky[\s\S]*failures/)
  expect(ran.text).not.toContain('repair')
  expect(seen.runs).toEqual([])
})

test('/xcrew history names the scheme and tests each duration belongs to', async ($, on) => {
  mock.store(on, { [historyKey(scopeKey('', 'test_sim · App › SmallTests'))]: [45_000], [historyKey(scopeKey('', 'build_sim'))]: [60_000] })
  engine(on)
  await start($)

  const ran = await runCommand($, 'xcrew', 'history')

  expect(ran.text).toBe('usual durations, over the last 10 runs of each tool\navg 1:00 · last 1:00 · 1 run  build_sim\navg 0:45 · last 0:45 · 1 run  test_sim · App › SmallTests')
})

/** The Xcode MCP's runs are kept whether or not the session has seen its scheme: a selection without one is named plainly. */
test('/xcrew history names a test selection without a scheme plainly', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  engine(on)
  on('session.surfaces', () => ({ value: [] }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('tool.call', async () => {
    await clock.advance(45_000)
    return { result: {}, text: 'ok' }
  })
  await start($)
  await callTool($, 'mcp__xcode__RunAllTests', { extraArgs: ['-only-testing:SmallTests'] })

  const ran = await runCommand($, 'xcrew', 'history')

  expect(ran.text).toBe('usual durations, over the last 10 runs of each tool\navg 0:45 · last 0:45 · 1 run  RunAllTests › SmallTests')
})
