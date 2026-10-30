import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Report } from './cli'
import { callTool, runCommand, stubCli } from './testing'

const PANE = {
  plugin: 'xcrew',
  component: 'Pane',
  requestId: 'xcrew-failures',
  props: { title: 'Failures', isFocused: false, bodyColumns: 80, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} },
} as const

const XCODE_TESTS_FAILED: Partial<Report> = {
  ok: false,
  detail: '3 of 5 failed · MacroProbeTests/testMacro()',
  failures: [
    { title: 'MacroProbeTests/testMacro()', message: 'Issue recorded: Macro expansion did not produce the expected expanded source', where: 'MacroProbeTests.swift:19' },
    { title: 'MacroProbeTests/testMacroWithStringLiteral()', message: 'Issue recorded: Macro expansion did not produce the expected expanded source', where: 'MacroProbeTests.swift:35' },
    { title: 'PlainTests/testConcatenation()', message: 'XCTAssertEqual failed: ("ab") is not equal to ("ba") - strings join left to right', where: 'PlainTests.swift:5' },
  ],
}
const BUILD_FAILED: Partial<Report> = { ok: false, failures: [{ title: 'MacroProbe.swift:13', message: "cannot convert value of type 'String' to specified type 'Int'" }] }
const TESTS_FAILED: Partial<Report> = { ok: false, failures: [{ title: 'PlainTests/testConcatenation', message: 'XCTAssertEqual failed', where: 'PlainTests.swift:5' }] }
const PASSED: Partial<Report> = { ok: true, detail: '5 passed' }

/** Stands for the engine and the CLI: each call's report is the next of `reports`; records the panes opened. */
function engine(on: On, reports: Partial<Report>[]) {
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
  stubCli(on, { reports })
  on('tool.call', () => ({ result: {}, text: 'the server\'s result' }))
  return { opened, closed }
}

test('/xcrew failures opens a pane listing every failure of the last failing run', async ($, on) => {
  const seen = engine(on, [XCODE_TESTS_FAILED])
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

test('a failed test lists its images under it, and how many more there are and where', async ($, on) => {
  const images = ['/cache/images/run/CardTests/testCard/reference.png', '/cache/images/run/CardTests/testCard/failure.png', '/cache/images/run/CardTests/testCard/difference.png']
  const more = 'and 2 more images in /cache/images/run/CardTests/testCard'
  engine(on, [{ ok: false, failures: [{ title: 'CardTests/testCard', message: 'Snapshot does not match reference.', where: 'CardTests.swift:12', isTest: true, images, moreImages: more }] }])
  await callTool($, 'mcp__xcode__RunAllTests')
  await runCommand($, 'xcrew', 'failures')

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  for (const path of images) expect((await ui.find({ type: 'Text', text: path }))?.props.color).toBe('subtle')
  expect((await ui.find({ type: 'Text', text: more }))?.props.color).toBe('subtle')
  await ui.unmount()
})

test('a passing run of the same tool clears the list', async ($, on) => {
  engine(on, [XCODE_TESTS_FAILED, PASSED])
  await callTool($, 'mcp__xcode__RunAllTests')
  await callTool($, 'mcp__xcode__RunAllTests')

  const ran = await runCommand($, 'xcrew', 'failures')

  expect(ran.text).toBe('No failures in the last runs.')
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('No failures in the last runs.')
  await ui.unmount()
})

test('another tool passing leaves the list from the one that failed', async ($, on) => {
  engine(on, [BUILD_FAILED, PASSED])
  await callTool($, 'mcp__MobileBuildMCP__build_sim')
  await callTool($, 'mcp__xcode__RunAllTests')

  const ran = await runCommand($, 'xcrew', 'failures')

  expect(ran.text).toBe('1 failure from build_sim, in the pane.')
})

test('a passing run on another scheme leaves the failures it never re-ran', async ($, on) => {
  engine(on, [TESTS_FAILED, PASSED])
  await callTool($, 'mcp__MobileBuildMCP__test_sim', { scheme: 'Payments' })
  await callTool($, 'mcp__MobileBuildMCP__test_sim', { scheme: 'Profile' })

  const ran = await runCommand($, 'xcrew', 'failures')

  expect(ran.text).toBe('1 failure from test_sim · Payments, in the pane.')
})

test('once the failing run passes, the pane closes: it has nothing left to show', async ($, on) => {
  const seen = engine(on, [TESTS_FAILED, PASSED])
  await callTool($, 'mcp__MobileBuildMCP__test_sim', { scheme: 'Payments' })
  await runCommand($, 'xcrew', 'failures')
  await callTool($, 'mcp__MobileBuildMCP__test_sim', { scheme: 'Payments' })

  expect(seen.closed).toEqual(['xcrew-failures'])
})

test('/xcrew close closes the pane from the prompt, where its mark can\'t be clicked', async ($, on) => {
  const seen = engine(on, [TESTS_FAILED])
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  await runCommand($, 'xcrew', 'failures')

  const ran = await runCommand($, 'xcrew', 'close')

  expect(seen.closed).toEqual(['xcrew-failures'])
  expect(ran.text).toBe('Closed the failures pane.')
})

const BAND = {
  plugin: 'xcrew',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: true, maxRows: 10, bodyColumns: 100, scroll: { offset: 0, bodyRows: 10 }, view: {} },
} as const

/** The band's line as it reads, after the calls made so far. */
async function bandText($: Engine): Promise<string> {
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  return (await ui.findAll({ type: 'Text' })).map(text => text.text).join('')
}

test('after a failing run the band says where its failures are, and the pane stays closed until asked', async ($, on) => {
  const seen = engine(on, [TESTS_FAILED])
  await callTool($, 'mcp__MobileBuildMCP__test_sim')

  expect(await bandText($)).toEndWith(' · /xcrew failures')
  expect(seen.opened).toEqual([])
})

test('a passing run, or a failure with nothing to list, points nowhere', async ($, on) => {
  engine(on, [PASSED, { ok: false, failures: [] }])
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  expect(await bandText($)).not.toContain('/xcrew failures')
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  expect(await bandText($)).not.toContain('/xcrew failures')
})
