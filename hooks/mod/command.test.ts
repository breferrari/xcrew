import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'
import { runCommand } from './testing'

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
    runs.push(e.argv)
    return { value: { exitCode: 0, stdout: outputs[e.argv[1] ?? ''] ?? '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
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

test('/xcrew doctor shows the doctor\'s report without a turn for Claude', async ($, on) => {
  mock.store(on)
  const seen = engine(on, { doctor: 'ok    xcode-mcp/headless-enabled  enabled\nwarn  xcode-mcp/macro-copy-phase  TRMacros…\n' })
  await start($)

  const ran = await runCommand($, 'xcrew', 'doctor')

  expect(seen.runs.map(argv => argv.slice(1))).toEqual([['doctor']])
  expect(seen.runs[0]?.[0]).toMatch(/\/bin\/xcrew$/)
  expect(ran.text).toContain('warn  xcode-mcp/macro-copy-phase')
  expect(ran.context).toBeUndefined()
})

test('/xcrew repair re-copies dead macro plugins and shows what it did', async ($, on) => {
  mock.store(on)
  const seen = engine(on, { 'repair-macros': 'all 12 macro plugins answer\n' })
  await start($)

  const ran = await runCommand($, 'xcrew', 'repair')

  expect(seen.runs.map(argv => argv.slice(1))).toEqual([['repair-macros']])
  expect(ran.text).toContain('all 12 macro plugins answer')
})

test('/xcrew history lists each tool\'s usual duration, slowest first', async ($, on) => {
  mock.store(on, {
    'durations.build_sim': [60_000, 80_000],
    'durations.RunAllTests': [300_000],
    'other.key': 1,
  })
  engine(on)
  await start($)

  const ran = await runCommand($, 'xcrew', 'history')

  expect(ran.text).toBe('usual durations, over the last 10 runs of each tool\nRunAllTests  avg 5:00 · last 5:00 · 1 run\nbuild_sim    avg 1:10 · last 1:20 · 2 runs')
})

test('/xcrew history with nothing timed yet says so', async ($, on) => {
  mock.store(on)
  engine(on)
  await start($)
  const ran = await runCommand($, 'xcrew', 'history')
  expect(ran.text).toBe('No builds or test runs timed yet.')
})

test('/xcrew alone lists what it can do', async ($, on) => {
  mock.store(on)
  const seen = engine(on)
  await start($)
  const ran = await runCommand($, 'xcrew')
  expect(ran.text).toMatch(/doctor[\s\S]*repair[\s\S]*history/)
  expect(seen.runs).toEqual([])
})
