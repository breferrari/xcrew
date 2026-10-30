import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'
import { historyKey, scopeKey, testsKey } from './timing'
import { callTool, runCommand, stubCli } from './testing'
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
    const time = await ui.find({ type: 'Text', text: /^0:41$/ })
    drawn = { dot: dot?.props.color, tool: tool?.props.weight, time: time?.text }
    await ui.unmount()
    return { result: {}, text: captured.mobileTestsPassed.text }
  })

  await callTool($, 'mcp__MobileBuildMCP__test_sim')

  expect(drawn).toEqual({ dot: '#ec501d', tool: 'semibold', time: '0:41' })
  expect(statuses.filter(Boolean)).toEqual([])
})

test('when it ends the band shows the outcome: success green, failure and its detail red', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  inTerminal(on)
  on('ui.status', () => ({ value: undefined }))
  stubCli(on, { reports: [{ ok: true, detail: '3 passed' }, { ok: false, detail: "MacroProbe.swift:13 Cannot convert value of type 'String' to specified type 'Int'" }] })
  on('tool.call', async () => {
    await clock.advance(12_000)
    return { result: {}, text: 'the server\'s result' }
  })

  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  let ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: '✓' }))?.props.color).toBe('success')
  expect((await ui.find({ type: 'Text', text: /^3 passed$/ }))?.props.color).toBeUndefined()
  await ui.unmount()

  await callTool($, 'mcp__xcode__BuildProject')
  ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: '✗' }))?.props.color).toBe('error')
  expect((await ui.find({ type: 'Text', text: /^MacroProbe\.swift:13/ }))?.props.color).toBe('error')
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
  mock.store(on, { [historyKey(scopeKey('', 'build_sim · App'))]: [10_000, 10_000, 10_000, 10_000, 10_000] })
  inTerminal(on)
  on('ui.status', () => ({ value: undefined }))
  on('tool.call', async () => {
    await clock.advance(15_000)
    return { result: {}, text: 'ok' }
  })

  await callTool($, 'mcp__MobileBuildMCP__build_sim', { scheme: 'App' })

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /^\(1\.5× its usual 0:10\)$/ }))?.props.color).toBe('#ec501d')
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

test('the band carries the phase after the time, in the theme\'s text colour', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on, { [testsKey(scopeKey('', 'test_sim · App'))]: 959 })
  inTerminal(on)
  on('ui.status', () => ({ value: undefined }))
  stubCli(on, { phase: () => ({ log: '/logs/test_sim_1.log', phase: 'testing 1 of 959' }) })
  let phase: unknown
  on('tool.call', async () => {
    await clock.advance(3_000)
    const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
    phase = (await ui.find({ type: 'Text', text: /^testing 1 of 959$/ }))?.props.color
    await ui.unmount()
    return { result: {}, text: captured.mobileTestsPassed.text }
  })

  await callTool($, 'mcp__MobileBuildMCP__test_sim')

  expect(phase).toBeUndefined()
})

test('only the separators are faint: the time, the time left, the phase and the target read in the theme\'s text colour', () => {
  const running = segments({ tool: 'test_sim', target: 'App on iPhone 18 | Unit', startedAt: 0, measuredFrom: 0, usual: 110_000, phase: 'preparing' }, 44_000)
  const ended = segments({ tool: 'test_sim', target: 'App on iPhone 18 | Unit', startedAt: 0, ended: { at: 50_000, elapsed: 50_000, ok: true, detail: '3 passed' } }, 50_000)
  for (const drawn of [running, ended]) {
    const faint = drawn.filter(segment => segment.color === 'subtle')
    expect(faint.length).toBeGreaterThan(0)
    expect(faint.every(segment => segment.text === ' · ')).toBe(true)
  }
  for (const value of ['0:44', '~1:06 left', 'preparing', 'App on iPhone 18 | Unit']) {
    expect([value, running.find(segment => segment.text.trim() === value)?.color]).toEqual([value, undefined])
  }
  for (const value of ['0:50', '3 passed', 'App on iPhone 18 | Unit']) {
    expect([value, ended.find(segment => segment.text.trim() === value)?.color]).toEqual([value, undefined])
  }
})

test('a finished run ends with its target too, so a narrow terminal cuts that before the outcome', () => {
  const drawn = segments({ tool: 'test_sim', target: 'App on iPhone 18 | Unit', startedAt: 0, ended: { at: 50_000, elapsed: 50_000, ok: false, detail: '3 of 961 failed', comparison: '(avg 0:45)', hasFailures: true } }, 50_000)
  expect(drawn.map(segment => segment.text).join('')).toBe('✗ test_sim · 0:50 (avg 0:45) · 3 of 961 failed · /xcrew failures · App on iPhone 18 | Unit')
})

test('a separator and its value are drawn as one text, so a narrow terminal cuts them together', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  inTerminal(on)
  on('ui.status', () => ({ value: undefined }))
  let joined: string | undefined
  on('tool.call', async () => {
    await clock.advance(41_000)
    const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
    joined = (await ui.find({ type: 'Text', text: ' · 0:41' }))?.text
    await ui.unmount()
    return { result: {}, text: captured.mobileTestsPassed.text }
  })

  await callTool($, 'mcp__MobileBuildMCP__test_sim')

  expect(joined).toBe(' · 0:41')
})

test('the time and phase come before the target, so a narrow terminal cuts what you already know', () => {
  const run = { tool: 'build_sim', target: 'App on iPhone 12', startedAt: 0, phase: 'compiling Utility' }
  expect(segments(run, 41_000).map(segment => segment.text)).toEqual(['●', ' ', 'build_sim', ' · ', '0:41', ' · ', 'compiling Utility', ' · ', 'App on iPhone 12'])
})

test('with a usual time to go by, the band draws a gauge and the time left after the clock', () => {
  const run = { tool: 'build_sim', target: 'App on iPhone 12', startedAt: 0, measuredFrom: 0, usual: 36_000, phase: 'compiling Net' }
  const drawn = segments(run, 21_000)
  expect(drawn.map(segment => segment.text)).toEqual(['●', ' ', 'build_sim', ' · ', '0:21', ' ', '━━━━╸', '───', ' ', '~0:15 left', ' · ', 'compiling Net', ' · ', 'App on iPhone 12'])
  expect(drawn.find(segment => segment.text === '━━━━╸')?.color).toBe('success')
  expect(drawn.find(segment => segment.text === '───')?.color).toBe('inactive')
})

test('past the usual time the gauge turns to the warning colour and says how far over', () => {
  const drawn = segments({ tool: 'test_sim', startedAt: 0, measuredFrom: 0, usual: 44_000 }, 52_000)
  expect(drawn.map(segment => segment.text)).toEqual(['●', ' ', 'test_sim', ' · ', '0:52', ' ', '━━━━━━━━', '', ' ', '0:08 over'])
  expect(drawn.find(segment => segment.text === '━━━━━━━━')?.color).toBe('warning')
  expect(drawn.find(segment => segment.text === '0:08 over')?.color).toBe('warning')
})

test('the gauge measures from when the run itself began, while the clock shows the whole wait', () => {
  const drawn = segments({ tool: 'test_sim', startedAt: 0, measuredFrom: 20_000, usual: 36_000 }, 41_000)
  expect(drawn.map(segment => segment.text)).toEqual(['●', ' ', 'test_sim', ' · ', '0:41', ' ', '━━━━╸', '───', ' ', '~0:15 left'])
})

test('before the run itself begins there is no gauge to draw', () => {
  const drawn = segments({ tool: 'test_sim', startedAt: 0, usual: 36_000, phase: 'preparing' }, 10_000)
  expect(drawn.map(segment => segment.text)).toEqual(['●', ' ', 'test_sim', ' · ', '0:10', ' · ', 'preparing'])
})

// MARK: How long a finished run stays

test('a passed run leaves the band three minutes after it ends, with nothing else happening', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  inTerminal(on)
  on('ui.status', () => ({ value: undefined }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return Text({ children: ['engine'] })
  })
  on('tool.call', () => ({ result: {}, text: captured.xcodeBuildPassed.text }))

  await callTool($, 'mcp__xcode__BuildProject')
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  await clock.advance(179_000)
  expect(await ui.find({ type: 'Text', text: /BuildProject/ })).toBeDefined()
  await clock.advance(2_000)
  expect(await ui.find({ type: 'Text', text: /BuildProject/ })).toBeUndefined()
  await ui.unmount()
})

test('a failed run stays for up to half an hour, since it asks for action', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  inTerminal(on)
  on('ui.status', () => ({ value: undefined }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return Text({ children: ['engine'] })
  })
  stubCli(on, { reports: [{ ok: false, detail: 'App.swift:3 Cannot find Foo in scope' }] })
  on('tool.call', () => ({ result: {}, isError: true, text: 'the server\'s result' }))

  await callTool($, 'mcp__xcode__BuildProject')
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  await clock.advance(29 * 60_000)
  expect(await ui.find({ type: 'Text', text: /BuildProject/ })).toBeDefined()
  await clock.advance(2 * 60_000)
  expect(await ui.find({ type: 'Text', text: /BuildProject/ })).toBeUndefined()
  await ui.unmount()
})

test('/xcrew close takes a failed run off the band', async ($, on) => {
  mock.clock(on)
  mock.store(on)
  inTerminal(on)
  on('ui.status', () => ({ value: undefined }))
  on('ui.close', () => ({ value: undefined }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return Text({ children: ['engine'] })
  })
  stubCli(on, { reports: [{ ok: false, detail: 'App.swift:3 Cannot find Foo in scope' }] })
  on('tool.call', () => ({ result: {}, isError: true, text: 'the server\'s result' }))

  await callTool($, 'mcp__xcode__BuildProject')
  await runCommand($, 'xcrew', 'close')
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /BuildProject/ })).toBeUndefined()
  await ui.unmount()
})

// MARK: Where the pointer to the failures goes

/** A 90-second test run with one failure, on `surface`; returns what was toasted and what was notified. */
async function longFailingRun($: Engine, on: On, surface: 'terminal' | 'vscode') {
  const clock = mock.clock(on)
  mock.store(on)
  on('session.surfaces', () => ({ value: [surface] }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.invalidate', () => ({ value: undefined }))
  const toasts: string[] = []
  const notes: string[] = []
  on('ui.toast', (_, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  on('ui.notify', (_, e) => {
    notes.push(e.text)
    return { value: { isSent: true, channel: 'terminal_bell' } }
  })
  stubCli(on, { reports: [{ ok: false, detail: '1 of 9 failed', failures: [{ title: 'testLogin', message: 'XCTAssertEqual failed' }] }] })
  on('tool.call', async () => {
    await clock.advance(90_000)
    return { result: {}, isError: true, text: 'the server\'s result' }
  })
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  return { toasts, notes }
}

test('where no band draws, the toast points at the failures and the notification carries the outcome alone', async ($, on) => {
  const { toasts, notes } = await longFailingRun($, on, 'vscode')
  expect(toasts).toEqual(['✗ test_sim · 1:30 · 1 of 9 failed · /xcrew failures'])
  expect(notes).toEqual(['✗ test_sim · 1:30 · 1 of 9 failed'])
})

test('where the band draws, it ends with the pointer and the notification carries the outcome alone', async ($, on) => {
  const { notes } = await longFailingRun($, on, 'terminal')
  expect(notes).toEqual(['✗ test_sim · 1:30 · 1 of 9 failed'])
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /\/xcrew failures/ })).toBeDefined()
  await ui.unmount()
})
