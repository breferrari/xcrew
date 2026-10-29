import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'
import { callTool, stubCli } from './testing'
import type { Report } from './cli'

const TEST_SIM = 'mcp__MobileBuildMCP__test_sim'

/** The result row under a tool call in the transcript, as the engine raises it for the call `id`. */
function resultRow(id: string, { tool = TEST_SIM, isExpanded = false as boolean | 'unsaid', surface = 'terminal' as 'terminal' | 'desktop' | 'vscode' } = {}) {
  const expanded = isExpanded === 'unsaid' ? {} : { isExpanded }
  return { plugin: 'xcrew', surface, component: 'ToolResult', requestId: id, props: { tool_use_id: id, tool, output: { content: [] }, isErrored: false, ...expanded } } as const
}

/** A session where every build or test call takes 12 s and the CLI reports `report`. The engine draws a row as the result Claude read. */
function session(on: On, report: Partial<Report>) {
  const clock = mock.clock(on)
  mock.store(on)
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.render', ($, e) => $.ui.resolve(e).Text({ children: ['the result Claude read'] }))
  stubCli(on, { reports: [report] })
  on('tool.call', async () => {
    await clock.advance(12_000)
    return { result: {}, text: 'the server output', ...(report.ok ? {} : { isError: true }) }
  })
}

/** A call under its own `tool_use_id`, which its result row is raised with. */
function run($: Engine, id: string, tool = TEST_SIM) {
  return callTool($, tool, { tool_use_id: id })
}

const failures = ['A/a()', 'B/b()', 'C/c()', 'D/d()', 'E/e()'].map((title, index) => ({ title, message: 'failed', where: `Tests.swift:${index + 1}` }))

test('a finished run draws its outcome in the transcript in place of the result', async ($, on) => {
  session(on, { ok: true, detail: '3 passed' })
  await run($, 'toolu_pass')

  for (const surface of ['terminal', 'desktop', 'vscode'] as const) {
    const ui = await $.ui.mount(resultRow('toolu_pass', { surface }))
    expect((await ui.find({ type: 'Text', text: '✓' }))?.props.color).toBe('success')
    expect((await ui.find({ type: 'Text', text: /^test_sim$/ }))?.props.weight).toBe('semibold')
    expect(await ui.find({ type: 'Text', text: /^3 passed$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'the result Claude read' })).toBeUndefined()
    await ui.unmount()
  }
})

test('a failing run lists its first failures and counts the rest', async ($, on) => {
  session(on, { ok: false, detail: '5 of 8 failed · A/a()', failures })
  await run($, 'toolu_fail', 'mcp__plugin_xcrew_MobileBuildMCP__test_sim')

  const ui = await $.ui.mount(resultRow('toolu_fail', { tool: 'mcp__plugin_xcrew_MobileBuildMCP__test_sim' }))
  expect((await ui.findAll({ type: 'Text', text: '✗' })).map(found => found.props.color)).toEqual(['error', 'error', 'error', 'error'])
  for (const shown of ['A/a()', 'B/b()', 'C/c()', /^Tests\.swift:3$/]) expect(await ui.find({ type: 'Text', text: shown })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'D/d()' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: '2 more' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /xcrew failures/ })).toBeUndefined()
  await ui.unmount()
})

test('expanded, or for a call the mod never saw, the row is the result Claude read', async ($, on) => {
  session(on, { ok: true, detail: '3 passed' })
  await run($, 'toolu_seen')

  for (const row of [resultRow('toolu_seen', { isExpanded: true }), resultRow('toolu_unseen'), resultRow('toolu_seen', { tool: 'mcp__xcode__XcodeRead' })]) {
    const ui = await $.ui.mount(row)
    expect(await ui.find({ type: 'Text', text: '✓' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: 'the result Claude read' })).toBeDefined()
    await ui.unmount()
  }
})

test('a row stays the result Claude read where the surface does not say it is collapsed', async ($, on) => {
  session(on, { ok: true, detail: '3 passed' })
  await run($, 'toolu_unsaid')

  const ui = await $.ui.mount(resultRow('toolu_unsaid', { isExpanded: 'unsaid', surface: 'desktop' }))
  expect(await ui.find({ type: 'Text', text: '✓' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'the result Claude read' })).toBeDefined()
  await ui.unmount()
})

test('a failure xcrew could not read keeps the result Claude read', async ($, on) => {
  session(on, { ok: false })
  await run($, 'toolu_unread')

  const ui = await $.ui.mount(resultRow('toolu_unread'))
  expect(await ui.find({ type: 'Text', text: '✗' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'the result Claude read' })).toBeDefined()
  await ui.unmount()
})

test('an app launch keeps its own output, which says where the app is and what it logged', async ($, on) => {
  session(on, { ok: true, detail: 'launched' })
  await run($, 'toolu_launch', 'mcp__MobileBuildMCP__launch_app_sim')

  const ui = await $.ui.mount(resultRow('toolu_launch', { tool: 'mcp__MobileBuildMCP__launch_app_sim' }))
  expect(await ui.find({ type: 'Text', text: '✓' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'the result Claude read' })).toBeDefined()
  await ui.unmount()
})

test('a run redraws only its own row', async ($, on) => {
  session(on, { ok: true, detail: '3 passed' })
  // Each drawing of the first row reads its outcome once; the run's own write reads it too, before the row is drawn.
  let reads = 0
  on('state.get', async ($, e, next) => {
    if (e.id === 'toolu_first') reads += 1
    return next(e)
  })
  await run($, 'toolu_first')
  reads = 0
  const first = await $.ui.mount(resultRow('toolu_first'))
  const drawnOnce = reads

  await run($, 'toolu_second')

  expect(drawnOnce).toBe(1)
  expect(reads).toBe(1)
  await first.unmount()
})
