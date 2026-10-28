import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import { callTool } from './testing'
import { segments } from './band'
import * as captured from './fixtures'

const BAND = {
  plugin: 'xcrew',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: true, maxRows: 10, bodyColumns: 100, scroll: { offset: 0, bodyRows: 10 }, view: {} },
} as const

/** A terminal session: the band draws there, so the status line isn't needed. */
function inTerminal(on: On) {
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.invalidate', () => ({ value: undefined }))
}

test('while a run is going the band shows it in colour, and the plain status line stays empty', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  inTerminal(on)
  const statuses: (string | undefined)[] = []
  on('ui.status', (_, e) => {
    statuses.push(e.text)
    return { value: undefined }
  })
  let drawn: { dot?: unknown; tool?: unknown; time?: string } = {}
  on('tool.call', async () => {
    await clock.advance(41_000)
    const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
    const dot = await ui.find({ type: 'Text', text: '●' })
    const tool = await ui.find({ type: 'Text', text: /^test_sim$/ })
    const time = await ui.find({ type: 'Text', text: /0:41/ })
    drawn = { dot: dot?.props.color, tool: tool?.props.weight, time: time?.text }
    await ui.unmount()
    return { result: {}, text: captured.mobileTestsPassed.text }
  })

  await callTool($, 'mcp__MobileBuildMCP__test_sim')

  expect(drawn).toEqual({ dot: '#ec501d', tool: 'semibold', time: ' · 0:41' })
  expect(statuses.filter(Boolean)).toEqual([])
})

test('when it ends the band shows the outcome: success green, failure and its detail red', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  inTerminal(on)
  on('ui.status', () => ({ value: undefined }))
  const answers = [captured.mobileTestsPassed, captured.xcodeBuildFailed]
  on('tool.call', async () => {
    await clock.advance(12_000)
    const next = answers.shift()!
    return { result: {}, text: next.text, ...(next.isError ? { isError: true } : {}) }
  })

  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  let ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: '✓' }))?.props.color).toBe('success')
  expect((await ui.find({ type: 'Text', text: / · 3 passed/ }))?.props.color).toBe('subtle')
  await ui.unmount()

  await callTool($, 'mcp__xcode__BuildProject')
  ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: '✗' }))?.props.color).toBe('error')
  expect((await ui.find({ type: 'Text', text: /MacroProbe\.swift:13/ }))?.props.color).toBe('error')
  await ui.unmount()
})

test('the band hides a few minutes after the run ends', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  inTerminal(on)
  on('ui.status', () => ({ value: undefined }))
  // Stands for Claude Code's own drawing, which shows when the band steps aside.
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return Text({ children: ['engine'] })
  })
  on('tool.call', () => ({ result: {}, text: captured.xcodeBuildPassed.text }))

  await callTool($, 'mcp__xcode__BuildProject')
  await clock.advance(4 * 60_000)

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /BuildProject/ })).toBeUndefined()
  await ui.unmount()
})

test('where no surface draws bands, the plain status line carries the run', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  on('session.surfaces', () => ({ value: ['vscode'] }))
  on('ui.toast', () => ({ value: undefined }))
  const statuses: (string | undefined)[] = []
  on('ui.status', (_, e) => {
    statuses.push(e.text)
    return { value: undefined }
  })
  on('tool.call', async () => {
    await clock.advance(3_000)
    return { result: {}, text: 'ok' }
  })

  await callTool($, 'mcp__xcode__BuildProject')

  expect(statuses).toContain('BuildProject running · 0:03')
})

test('a run far slower than usual shows it in the band', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on, { 'durations.build_sim': [10_000, 10_000, 10_000, 10_000, 10_000] })
  inTerminal(on)
  on('ui.status', () => ({ value: undefined }))
  on('tool.call', async () => {
    await clock.advance(15_000)
    return { result: {}, text: 'ok' }
  })

  await callTool($, 'mcp__MobileBuildMCP__build_sim')

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: ' (1.5× its usual 0:10)' }))?.props.color).toBe('#ec501d')
  await ui.unmount()
})

test('where the band draws, it carries the outcome alone, with no toast repeating it', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  const toasts: string[] = []
  on('ui.toast', (_, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  on('tool.call', async () => {
    await clock.advance(5_000)
    return { result: {}, text: captured.mobileTestsPassed.text }
  })

  await callTool($, 'mcp__MobileBuildMCP__test_sim')

  expect(toasts).toEqual([])
})

test('the band carries the phase after the time, in the quiet colour', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on, { 'tests.test_sim': 959 })
  mock.env(on, { HOME: '/Users/dev' })
  inTerminal(on)
  on('ui.status', () => ({ value: undefined }))
  on('session.root', () => ({ value: '/work/App' }))
  on('fs.list', (_, e) =>
    e.path?.endsWith('/workspaces')
      ? { value: [{ name: 'App-0000', kind: 'dir', size: 0, mtimeMs: 0, isLink: false }] }
      : { value: [{ name: 'test_sim_2026-10-28T19-10-02Z_pid1_aaaa.log', kind: 'file', size: 1, mtimeMs: clock.now(), isLink: false }] },
  )
  on('fs.read', () => ({ value: "Testing started\nTest case 'A.test_a()' passed on 'Clone 1' (0.001 seconds)\n" }))
  let phase: unknown
  on('tool.call', async () => {
    await clock.advance(3_000)
    const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
    phase = (await ui.find({ type: 'Text', text: ' · testing 1 of 959' }))?.props.color
    await ui.unmount()
    return { result: {}, text: captured.mobileTestsPassed.text }
  })

  await callTool($, 'mcp__MobileBuildMCP__test_sim')

  expect(phase).toBe('subtle')
})

test('the time and phase come before the target, so a narrow terminal cuts what you already know', () => {
  const run = { tool: 'build_sim', target: 'App on iPhone 12', startedAt: 0, phase: 'compiling Utility' }
  expect(segments(run, 41_000).map(segment => segment.text)).toEqual(['●', ' ', 'build_sim', ' · 0:41', ' · compiling Utility', ' · App on iPhone 12'])
})

test('with a usual time to go by, the band draws a gauge and the time left after the clock', () => {
  const run = { tool: 'build_sim', target: 'App on iPhone 12', startedAt: 0, usual: 36_000, phase: 'compiling Net' }
  const drawn = segments(run, 21_000)
  expect(drawn.map(segment => segment.text)).toEqual(['●', ' ', 'build_sim', ' · 0:21', ' ', '━━━━╸', '───', ' ~0:15 left', ' · compiling Net', ' · App on iPhone 12'])
  expect(drawn[5]?.color).toBe('success')
  expect(drawn[6]?.color).toBe('inactive')
})

test('past the usual time the gauge turns to the warning colour and says how far over', () => {
  const drawn = segments({ tool: 'test_sim', startedAt: 0, usual: 44_000 }, 52_000)
  expect(drawn.map(segment => segment.text)).toEqual(['●', ' ', 'test_sim', ' · 0:52', ' ', '━━━━━━━━', '', ' 0:08 over'])
  expect(drawn[5]?.color).toBe('warning')
  expect(drawn[7]?.color).toBe('warning')
})
