import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import { callTool, runCommand, stubCli } from './testing'

/**
 * A session whose CLI answers at once, but for `project --xcode`, which the first MobileBuildMCP call that names no
 * scheme awaits: it waits on `held` while the test moves the clock.
 */
function session(on: On, held?: Promise<void>) {
  const clock = mock.clock(on, { now: Date.UTC(2026, 10, 2, 10, 46, 55) })
  mock.store(on)
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  stubCli(on, {
    project: async args => {
      if (args.includes('--xcode')) await held
      return { isGenerated: false }
    },
  })
  on('tool.call', () => ({ result: {}, text: 'the server\'s result' }))
  return clock
}

const timings = async ($: Parameters<typeof runCommand>[0]) => String((await runCommand($, 'xcrew', 'timings')).text ?? '')

test('a call that waited a second or more before it started is kept, with each step it waited on', async ($, on) => {
  let release = () => {}
  const clock = session(on, new Promise<void>(resolve => (release = resolve)))
  const call = callTool($, 'mcp__MobileBuildMCP__test_sim')
  await clock.advance(1_500)
  release()
  await call
  const text = await timings($)
  expect(text).toContain('test_sim, 2026-11-02 10:46 UTC: 1.5 s before it started')
  expect(text).toMatch(/readXcodeStart 1\.5 s/)
})

test('a call that started at once keeps nothing', async ($, on) => {
  session(on)
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  expect(await timings($)).toBe('No build, test or run call has waited a second or more before it started.')
})

test('the twenty newest slow calls are kept, the newest listed first', async ($, on) => {
  const releases: (() => void)[] = []
  const clock = mock.clock(on, { now: Date.UTC(2026, 10, 2, 10, 0) })
  mock.store(on)
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  stubCli(on, { project: async args => {
    if (args.includes('--xcode')) await new Promise<void>(resolve => releases.push(resolve))
    return { isGenerated: false }
  } })
  on('tool.call', () => ({ result: {}, text: 'done' }))
  for (let index = 0; index < 22; index++) {
    const call = callTool($, 'mcp__MobileBuildMCP__test_sim')
    await clock.advance(1_000 + index * 100)
    while (releases.length > 0) releases.shift()?.()
    await call
  }
  const lines = (await timings($)).split('\n').filter(line => line.startsWith('- '))
  expect(lines).toHaveLength(20)
  expect(lines[0]).toContain('3.1 s before it started')
  expect(lines.at(-1)).toContain('1.2 s before it started')
})
