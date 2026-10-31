import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On, RenderSurface } from 'claude-code'
import { callTool, stubCli } from './testing'

const BAND = {
  plugin: 'xcrew',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: true, maxRows: 10, bodyColumns: 120, scroll: { offset: 0, bodyRows: 10 }, view: {} },
} as const
const TEST_SIM = 'mcp__MobileBuildMCP__test_sim'

function row(id: string) {
  return { plugin: 'xcrew', surface: 'terminal', component: 'ToolResult', requestId: id, props: { tool_use_id: id, tool: TEST_SIM, output: { content: [] }, isErrored: false, isExpanded: false } } as const
}

/** A session whose agents are `agents`, each by id with its own description, or whose list fails; the band drawn mid-run. */
function session($: Engine, on: On, agents: { id: string; description: string }[] | Error, surfaces: RenderSurface[] = ['terminal']) {
  const clock = mock.clock(on)
  mock.store(on)
  on('session.surfaces', () => ({ value: surfaces }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.invalidate', () => ({ value: undefined }))
  const statuses: (string | undefined)[] = []
  on('ui.status', (_, e) => {
    statuses.push(e.text)
    return { value: undefined }
  })
  on('ui.render', ($, e) => $.ui.resolve(e).Text({ children: ['the result Claude read'] }))
  on('agent.list', () => {
    if (agents instanceof Error) throw agents
    return { value: agents.map(agent => ({ ...agent, type: 'general-purpose', status: 'running' as const })) }
  })
  stubCli(on, { reports: [{ ok: true, detail: '3 passed' }] })
  let band = ''
  on('tool.call', async () => {
    await clock.advance(5_000)
    const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
    band = (await ui.findAll({ type: 'Text' })).map(text => text.text).join('')
    await ui.unmount()
    return { result: {}, text: 'the server output' }
  })
  return { band: () => band, statuses }
}

async function rowText($: Engine, id: string): Promise<string> {
  const ui = await $.ui.mount(row(id))
  const text = (await ui.findAll({ type: 'Text' })).map(text => text.text).join('')
  await ui.unmount()
  return text
}

test("a subagent's run says which, by its own description, on the band and on its row", async ($, on) => {
  const seen = session($, on, [{ id: 'a1', description: 'Fix login tests' }])
  await callTool($, TEST_SIM, { agentId: 'a1', tool_use_id: 'toolu_1' })
  expect(seen.band()).toContain(' · by "Fix login tests"')
  expect(await rowText($, 'toolu_1')).toContain(' · by "Fix login tests"')
})

test("the main loop's run carries no label", async ($, on) => {
  const seen = session($, on, [{ id: 'a1', description: 'Fix login tests' }])
  await callTool($, TEST_SIM, { tool_use_id: 'toolu_1' })
  expect(seen.band()).toContain('test_sim · 0:05')
  expect(seen.band()).not.toContain(' by ')
  expect(await rowText($, 'toolu_1')).not.toContain(' by ')
})

/** The description is the model's own words: shown as given, on one line, cut short, and never a word added. */
test('a long or multi-line description is collapsed to one line and cut to 40 characters', async ($, on) => {
  const seen = session($, on, [{ id: 'a1', description: 'Rewrite the login flow\n  and its   tests for the new session API' }])
  await callTool($, TEST_SIM, { agentId: 'a1', tool_use_id: 'toolu_1' })
  expect(seen.band()).toContain(' · by "Rewrite the login flow and its tests for…"')
})

/** Cut by what a reader counts as a character, so an emoji at the cut is kept whole or left out, never split. */
test('the cut never splits an emoji', async ($, on) => {
  const seen = session($, on, [{ id: 'a1', description: `${'a'.repeat(39)}🙂🙂 and more` }])
  await callTool($, TEST_SIM, { agentId: 'a1', tool_use_id: 'toolu_1' })
  expect(seen.band()).toContain(` · by "${'a'.repeat(39)}🙂…"`)
})

/** No substitute for a description that isn't there: no type, no name, no id. */
test("an agent the list doesn't name, or an empty description, gives no label", async ($, on) => {
  const seen = session($, on, [{ id: 'a2', description: '  ' }])
  await callTool($, TEST_SIM, { agentId: 'a1', tool_use_id: 'toolu_1' })
  expect(seen.band()).toContain('test_sim · 0:05')
  expect(seen.band()).not.toContain(' by ')
  await callTool($, TEST_SIM, { agentId: 'a2', tool_use_id: 'toolu_2' })
  expect(seen.band()).not.toContain(' by ')
})

test('a list that fails gives no label, and the run goes on', async ($, on) => {
  const seen = session($, on, new Error('no agents here'))
  const result = await callTool($, TEST_SIM, { agentId: 'a1', tool_use_id: 'toolu_1' })
  expect(result.text).toBe('the server output')
  expect(seen.band()).toContain('test_sim · 0:05')
  expect(seen.band()).not.toContain(' by ')
})

/** The plain status line, the toast and the notification keep their width for the outcome. */
test('the label is never on the plain status line', async ($, on) => {
  const seen = session($, on, [{ id: 'a1', description: 'Fix login tests' }], ['vscode'])
  await callTool($, TEST_SIM, { agentId: 'a1', tool_use_id: 'toolu_1' })
  expect(seen.statuses.some(text => text?.includes('Fix login tests'))).toBe(false)
})
