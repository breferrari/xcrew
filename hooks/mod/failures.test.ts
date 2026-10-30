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
const CAUSE =
  'xcrew: this build failed because of the Mac, not the code: a module in its DerivedData\'s module cache is corrupt ("malformed or corrupted precompiled file"). Remove ModuleCache.noindex and SDKExplicitPrecompiledModules from the DerivedData this build used, then build again'
const MAC_FAILED: Partial<Report> = { ...BUILD_FAILED, cause: CAUSE }
const MAC_ONLY: Partial<Report> = { ok: false, failures: [], cause: CAUSE }

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

test('a run the Mac failed opens its pane with the cause, ahead of its failures', async ($, on) => {
  engine(on, [MAC_FAILED])
  await callTool($, 'mcp__MobileBuildMCP__build_sim')

  const ran = await runCommand($, 'xcrew', 'failures')

  expect(ran.text).toBe("1 failure from build_sim, in the pane, after the Mac's cause.")
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const first = await ui.find({ type: 'Text' })
  expect(first?.text).toBe(CAUSE)
  expect(first?.props.color).toBe('warning')
  expect((await ui.find({ type: 'Text', text: 'MacroProbe.swift:13' }))?.props.color).toBe('error')
  await ui.unmount()
})

/** A build the Mac failed may list no compile error: its cause alone is what the pane holds, and the band points to it. */
test('a cause with no failures listed still leaves the pane its cause', async ($, on) => {
  engine(on, [MAC_ONLY])
  await callTool($, 'mcp__MobileBuildMCP__build_sim')

  expect(await bandText($)).toEndWith(' · /xcrew failures')
  expect((await runCommand($, 'xcrew', 'failures')).text).toBe("The Mac's cause from build_sim, in the pane.")
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: CAUSE }))?.props.color).toBe('warning')
  await ui.unmount()
})

test("a passing run of the same tool clears the Mac's cause too", async ($, on) => {
  const seen = engine(on, [MAC_ONLY, PASSED])
  await callTool($, 'mcp__MobileBuildMCP__build_sim')
  expect((await runCommand($, 'xcrew', 'failures')).text).toBe("The Mac's cause from build_sim, in the pane.")
  await callTool($, 'mcp__MobileBuildMCP__build_sim')

  expect(seen.closed).toEqual(['xcrew-failures'])
  expect((await runCommand($, 'xcrew', 'failures')).text).toBe('No failures in the last runs.')
})

/** The pane holds the last failing run: one the Mac failed replaces another scope's failures, as listed errors do. */
test("a run the Mac failed takes the pane from another scope's failures", async ($, on) => {
  engine(on, [TESTS_FAILED, MAC_ONLY])
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  await callTool($, 'mcp__MobileBuildMCP__build_sim')

  expect((await runCommand($, 'xcrew', 'failures')).text).toBe("The Mac's cause from build_sim, in the pane.")
})

/** A failing run with neither a failure nor a cause has nothing to show, and leaves what the pane held. */
test('a failure with nothing to list and no cause keeps the earlier list', async ($, on) => {
  engine(on, [MAC_FAILED, { ok: false, failures: [] }])
  await callTool($, 'mcp__MobileBuildMCP__build_sim')
  await callTool($, 'mcp__MobileBuildMCP__test_sim')

  expect((await runCommand($, 'xcrew', 'failures')).text).toBe("1 failure from build_sim, in the pane, after the Mac's cause.")
})
