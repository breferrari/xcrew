import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import { replays } from './replays'
import { callTool, mapStore, stubCli, type CliCall } from './testing'

/**
 * Real MobileBuildMCP test runs from the test bed, as the mod gets them: each result's text, with the CLI answering what
 * `xcrew report` answers for it (`replays.ts`, held to the CLI and to MobileBuildMCP's counts by TestbedReplayTests).
 */
type Replay = (typeof replays)[keyof typeof replays]

const TEST_SIM = 'mcp__plugin_xcrew_MobileBuildMCP__test_sim'

const BAND = {
  plugin: 'xcrew',
  component: 'AbovePrompt',
  surface: 'terminal',
  props: { hasSurvey: false, isWorking: true, maxRows: 10, bodyColumns: 100, scroll: { offset: 0, bodyRows: 10 }, view: {} },
} as const

/** A session on a branch whose test_sim answers `replay`'s text each time, and whose CLI reports on it as the golden says. */
function session(on: On, replay: Replay): { toasts: string[]; cli: CliCall[]; store: Map<string, unknown> } {
  const project = (args: readonly string[]) => ({
    isGenerated: false,
    ...(args.includes('--profiles') ? { scheme: 'App' } : {}),
    ...(args.includes('--branch') ? { root: '/work/App', branch: 'feat/replay' } : {}),
  })
  const seen = { toasts: [] as string[], cli: stubCli(on, { reports: [replay.report], phase: () => ({}), project }), store: mapStore(on) }
  const clock = mock.clock(on)
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('ui.toast', (_, e) => {
    seen.toasts.push(e.text)
    return { value: undefined }
  })
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.render', ($, e) => $.ui.resolve(e).Text({ children: ['the result Claude read'] }))
  on('tool.call', async () => {
    await clock.advance(2_000)
    return { result: {}, text: replay.text, ...(replay.isError ? { isError: true } : {}) }
  })
  return seen
}

function resultRow(id: string) {
  return { plugin: 'xcrew', surface: 'terminal', component: 'ToolResult', requestId: id, props: { tool_use_id: id, tool: TEST_SIM, output: { content: [] }, isErrored: false, isExpanded: false } } as const
}

for (const [name, replay, mark, time, detail, firstFailure] of [
  ['serial', replays.serial, '✗', '0:14', '2 of 4 failed · ProbeTests/testFails', 'ProbeTests/testFails'],
  ['shapes', replays.shapes, '✗', '0:15', '1 of 5 failed · ShapesTests/fails', 'ShapesTests/fails'],
  ['swift-testing', replays['swift-testing'], '✓', '0:07', '1 passed', undefined],
  ['profile', replays.profile, '✓', '0:04', '1 passed', undefined],
] as const) {
  test(`the ${name} run's text reaches the CLI as the server gave it, and its outcome shows on the band and in the row`, async ($, on) => {
    const seen = session(on, replay)
    await callTool($, TEST_SIM, { tool_use_id: `toolu_${name}` })

    const reported = seen.cli.filter(call => call.args[0] === 'report')
    expect(reported.map(call => call.args)).toEqual([['report', '--server', 'MobileBuildMCP', '--kind', 'test', ...(replay.isError ? ['--error'] : [])]])
    expect(reported[0]?.stdin).toBe(replay.text)
    expect(seen.toasts).toEqual([])

    const band = await $.ui.mount(BAND)
    expect((await band.find({ type: 'Text', text: mark }))?.props.color).toBe(mark === '✓' ? 'success' : 'error')
    for (const shown of [/^test_sim$/, time, detail]) expect(await band.find({ type: 'Text', text: shown })).toBeDefined()
    await band.unmount()

    const ui = await $.ui.mount(resultRow(`toolu_${name}`))
    expect(await ui.find({ type: 'Text', text: detail })).toBeDefined()
    if (firstFailure) expect(await ui.find({ type: 'Text', text: firstFailure })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'the result Claude read' })).toBeUndefined()
    await ui.unmount()
  })
}

for (const name of ['swift-testing', 'profile'] as const) {
  test(`after the passing ${name} run, the next run counts its progress out of the 1 test it ran`, async ($, on) => {
    const seen = session(on, replays[name])
    await callTool($, TEST_SIM)
    await callTool($, TEST_SIM)

    const phases = seen.cli.filter(call => call.args[0] === 'phase').map(call => call.args)
    expect(phases[0]).not.toContain('--expected')
    const last = phases.at(-1) ?? []
    expect(last[last.indexOf('--expected') + 1]).toBe('1')
  })
}

test('the serial run\'s failures enter the ledger under the target its result bundle names', async ($, on) => {
  const { store } = session(on, replays.serial)
  await callTool($, TEST_SIM)
  const ledger = store.get('ledger./work/App @ feat/replay') as { entries: { test: string; target?: string }[] } | undefined
  expect(ledger?.entries.map(entry => [entry.test, entry.target])).toEqual([['ProbeTests/testFails', 'FeatureTests'], ['ProbeTests/testFlaky', 'FeatureTests']])
})

test('the serial run\'s expected failure reaches Claude as a note beside the result', async ($, on) => {
  session(on, replays.serial)
  const result = await callTool($, TEST_SIM)
  expect(result.context).toContain('xcrew: 1 test also ran as an expected failure (XCTExpectFailure): ProbeTests/testExpectedFailure(). They count as neither passed nor failed in the result: 5 tests ran in all.')
})

/** The known-issue note's wording is held by its own tests; here, only that it names the test. */
test('the shapes run\'s known issue reaches Claude as a note beside the result', async ($, on) => {
  session(on, replays.shapes)
  const result = await callTool($, TEST_SIM)
  expect(result.context?.some(note => note.includes('ShapesTests/knownIssue()'))).toBe(true)
})
