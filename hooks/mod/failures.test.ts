import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import * as captured from './fixtures'
import { callTool, runCommand } from './testing'

const PANE = {
  plugin: 'xcrew',
  component: 'Pane',
  requestId: 'xcrew-failures',
  props: { title: 'Failures', isFocused: false, bodyColumns: 80, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} },
} as const

/** Stands for the engine: answers each call with the next captured result, and records the panes opened. */
function engine(on: On, answers: { isError: boolean; text: string }[]) {
  const opened: string[] = []
  const closed: string[] = []
  mock.clock(on)
  mock.store(on)
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.open', (_, e) => {
    opened.push(e.id)
    return { value: { isPlaced: true } }
  })
  on('ui.close', (_, e) => {
    closed.push(e.id)
    return { value: undefined }
  })
  on('tool.call', () => {
    const next = answers.shift()!
    return { result: {}, text: next.text, ...(next.isError ? { isError: true } : {}) }
  })
  return { opened, closed }
}

test('/xcrew failures opens a pane listing every failure of the last failing run', async ($, on) => {
  const seen = engine(on, [captured.xcodeTestsFailed])
  await callTool($, 'mcp__xcode__RunAllTests')

  const ran = await runCommand($, 'xcrew', 'failures')

  expect(seen.opened).toEqual(['xcrew-failures'])
  expect(ran.text).toBe('3 failures from RunAllTests, in the pane.')
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: 'MacroProbeTests/testMacro()' }))?.props.color).toBe('error')
  expect((await ui.find({ type: 'Text', text: /XCTAssertEqual failed/ }))?.text).toContain('strings join left to right')
  expect((await ui.find({ type: 'Text', text: /PlainTests\.swift:5/ }))?.props.color).toBe('subtle')
  await ui.unmount()
})

test('a passing run of the same tool clears the list', async ($, on) => {
  engine(on, [captured.xcodeTestsFailed, captured.xcodeTestsPassed])
  await callTool($, 'mcp__xcode__RunAllTests')
  await callTool($, 'mcp__xcode__RunAllTests')

  const ran = await runCommand($, 'xcrew', 'failures')

  expect(ran.text).toBe('No failures in the last runs.')
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('No failures in the last runs.')
  await ui.unmount()
})

test('another tool passing leaves the list from the one that failed', async ($, on) => {
  engine(on, [captured.mobileBuildFailed, captured.xcodeTestsPassed])
  await callTool($, 'mcp__MobileBuildMCP__build_sim')
  await callTool($, 'mcp__xcode__RunAllTests')

  const ran = await runCommand($, 'xcrew', 'failures')

  expect(ran.text).toBe('1 failure from build_sim, in the pane.')
})

test('a passing run on another scheme leaves the failures it never re-ran', async ($, on) => {
  engine(on, [captured.mobileTestsFailed, captured.mobileTestsPassed])
  await callTool($, 'mcp__MobileBuildMCP__test_sim', { scheme: 'Payments' })
  await callTool($, 'mcp__MobileBuildMCP__test_sim', { scheme: 'Profile' })

  const ran = await runCommand($, 'xcrew', 'failures')

  expect(ran.text).toBe('1 failure from test_sim · Payments, in the pane.')
})

test('once the failing run passes, the pane closes: it has nothing left to show', async ($, on) => {
  const seen = engine(on, [captured.mobileTestsFailed, captured.mobileTestsPassed])
  await callTool($, 'mcp__MobileBuildMCP__test_sim', { scheme: 'Payments' })
  await runCommand($, 'xcrew', 'failures')
  await callTool($, 'mcp__MobileBuildMCP__test_sim', { scheme: 'Payments' })

  expect(seen.closed).toEqual(['xcrew-failures'])
})

test('/xcrew close closes the pane from the prompt, where its mark can\'t be clicked', async ($, on) => {
  const seen = engine(on, [captured.mobileTestsFailed])
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  await runCommand($, 'xcrew', 'failures')

  const ran = await runCommand($, 'xcrew', 'close')

  expect(seen.closed).toEqual(['xcrew-failures'])
  expect(ran.text).toBe('Closed the failures pane.')
})
