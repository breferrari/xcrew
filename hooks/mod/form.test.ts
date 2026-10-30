import { expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On, RenderSurface } from 'claude-code'
import { mapStore, runCommand, stubCli, submitPrompt } from './testing'

const PANE = {
  plugin: 'xcrew',
  component: 'Pane',
  requestId: 'xcrew-setup',
  props: { title: 'xcrew setup', isFocused: false, bodyColumns: 100, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} },
} as const

/** What `xcrew setup --choices` gives for a modular app: four module schemes, two simulators, no config yet. */
const CHOICES = {
  container: 'Field.xcworkspace',
  containers: ['Field.xcworkspace'],
  schemes: [
    { name: 'App', container: 'Modules/App/App.xcodeproj', roles: ['app', 'unit-tests', 'ui-tests'], app: 'App' },
    { name: 'Core', container: 'Modules/Core/Core.xcodeproj', roles: ['unit-tests'] },
  ],
  picks: { appScheme: 'App', uiScheme: 'App', testScheme: 'App', bundleID: 'dev.example.App', testSimulator: 'iPhone 18' },
  simulators: [{ name: 'iPhone 18', runtime: '27.2' }, { name: 'iPhone Duo', runtime: '27.2', twoDisplays: true }],
}

/** A session that draws in the terminal, with the CLI answering `choices` and printing `wrote` for a write. */
async function session($: Engine, on: On, choices: unknown = CHOICES, surfaces: RenderSurface[] = ['terminal'], placed = true, after: unknown = choices) {
  mapStore(on)
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => ({ value: { tool: `mcp__xcrew__${e.name}` } }))
  on('session.surfaces', () => ({ value: surfaces }))
  const opened: string[] = []
  on('ui.open', (_, e) => {
    opened.push(e.id)
    return { value: placed ? { isPlaced: true } : { isPlaced: false, reason: 'the terminal is too narrow' } }
  })
  let wrote = false
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('prompt.submit', (_, e) => ({ text: e.text, context: e.context }))
  const calls = stubCli(on, { setup: args => (args.includes('--choices') ? (wrote ? after : choices) : ((wrote = true), 'xcrew: wrote .mobilebuildmcp/config.yaml for Field.xcworkspace; restart Claude Code so MobileBuildMCP reads it')) })
  await $.session.start({ cwd: '/project', surface: 'terminal', isInteractive: true })
  return { calls, opened }
}

test('/xcrew setup opens the form with setup\'s own picks', async ($, on) => {
  const { opened } = await session($, on)
  const answer = await runCommand($, 'xcrew', 'setup')
  expect(opened).toContain('xcrew-setup')
  expect(answer).toMatchObject({ text: expect.stringContaining('pane') })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Select', key: 'app-scheme' }))?.props).toMatchObject({ value: 'App' })
  expect((await ui.find({ type: 'Select', key: 'test-simulator' }))?.props).toMatchObject({ value: 'iPhone 18' })
  expect((await ui.find({ type: 'Input', key: 'bundle-id' }))?.props).toMatchObject({ value: 'dev.example.App' })
  await ui.unmount()
})

test('each scheme says what it does, and a two-display simulator says screenshots fail on it', async ($, on) => {
  await session($, on)
  await runCommand($, 'xcrew', 'setup')
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const schemes = (await ui.find({ type: 'Select', key: 'app-scheme' }))?.props as { options: { value: string; label?: string }[] }
  expect(schemes.options.map(option => option.label)).toEqual(['App · builds the app, runs unit tests, runs UI tests', 'Core · runs unit tests'])
  const simulators = (await ui.find({ type: 'Select', key: 'test-simulator' }))?.props as { options: { value: string; label?: string }[] }
  expect(simulators.options.map(option => option.value)).toEqual(['iPhone 18', 'iPhone Duo'])
  expect(simulators.options[1]?.label).toContain('two displays')
  await ui.unmount()
})

test('writing runs setup with exactly the picks', async ($, on) => {
  const { calls } = await session($, on)
  await runCommand($, 'xcrew', 'setup')
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.select({ key: 'test-scheme', value: 'Core' })
  await ui.input({ key: 'bundle-id', text: 'dev.example.Other' })
  await ui.press({ key: 'write' })
  const write = calls.find(call => call.args[0] === 'setup' && !call.args.includes('--choices'))
  expect(write?.args).toEqual(['setup', '--container', 'Field.xcworkspace', '--app-scheme', 'App', '--bundle-id', 'dev.example.Other', '--ui-scheme', 'App', '--test-scheme', 'Core', '--test-simulator', 'iPhone 18', '--debugger-backend', 'dap'])
  expect(await ui.find({ type: 'Text', text: /wrote \.mobilebuildmcp\/config\.yaml/ })).toBeDefined()
  await ui.unmount()
})

test('a config xcrew didn\'t write is replaced only through its own button, with --force', async ($, on) => {
  const { calls } = await session($, on, { ...CHOICES, config: { owner: 'other', scheme: 'Mine' } })
  await runCommand($, 'xcrew', 'setup')
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Button', key: 'write' }))?.text).toBe('Replace config (a backup is kept)')
  await ui.press({ key: 'write' })
  expect(calls.find(call => call.args[0] === 'setup' && !call.args.includes('--choices'))?.args.at(-1)).toBe('--force')
  await ui.unmount()
})

test('a project with no shared scheme names the skill and offers no scheme', async ($, on) => {
  await session($, on, { ...CHOICES, schemes: [], picks: { testSimulator: 'iPhone 18' } })
  await runCommand($, 'xcrew', 'setup')
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Select', key: 'app-scheme' })).toBeUndefined()
  expect((await ui.find({ type: 'Text', text: /no shared scheme/ }))?.text).toContain('/xcrew:setup')
  await ui.unmount()
})

test('a linked worktree writes its config from the main checkout\'s', async ($, on) => {
  const { calls } = await session($, on, { ...CHOICES, worktree: true })
  await runCommand($, 'xcrew', 'setup')
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.select({ key: 'worktree-simulator', value: 'fresh' })
  await ui.press({ key: 'write' })
  expect(calls.find(call => call.args[0] === 'setup' && !call.args.includes('--choices'))?.args).toEqual(['setup', '--worktree', '--fresh-simulator'])
  await ui.unmount()
})

test('picking another container reads its choices', async ($, on) => {
  const { calls } = await session($, on, { containers: ['ios/App.xcodeproj', 'macos/App.xcodeproj'], containerProblem: 'several projects a folder or two down (ios/App.xcodeproj, macos/App.xcodeproj): pass --container', schemes: [], picks: {}, simulators: [] })
  await runCommand($, 'xcrew', 'setup')
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /several projects/ })).toBeDefined()
  await ui.select({ key: 'container', value: 'macos/App.xcodeproj' })
  expect(calls.filter(call => call.args.includes('--choices')).at(-1)?.args).toEqual(['setup', '--choices', '--container', 'macos/App.xcodeproj'])
  await ui.unmount()
})

test('after a write, Claude reads once that MobileBuildMCP reads the new config at the next start', async ($, on) => {
  await session($, on)
  await runCommand($, 'xcrew', 'setup')
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.press({ key: 'write' })
  await ui.unmount()
  const first = await submitPrompt($, 'build it')
  expect(first).toMatchObject({ context: ['The person wrote a new MobileBuildMCP config with /xcrew setup; MobileBuildMCP reads it when Claude Code next starts.'] })
  const second = await submitPrompt($, 'and again')
  expect((second as { context?: readonly string[] }).context ?? []).toEqual([])
})

test('where nothing draws pickers, /xcrew setup names the skill and opens nothing', async ($, on) => {
  const { opened } = await session($, on, CHOICES, ['mobile'])
  const answer = await runCommand($, 'xcrew', 'setup')
  expect(opened).not.toContain('xcrew-setup')
  expect(answer).toMatchObject({ text: expect.stringContaining('/xcrew:setup') })
})

test('a scheme the workspace and its project both share is offered once', async ($, on) => {
  await session($, on, { ...CHOICES, schemes: [...CHOICES.schemes, { name: 'App', container: 'Field.xcworkspace', roles: ['app'], app: 'App' }] })
  await runCommand($, 'xcrew', 'setup')
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const schemes = (await ui.find({ type: 'Select', key: 'app-scheme' }))?.props as { options: { value: string }[] }
  expect(schemes.options.map(option => option.value)).toEqual(['App', 'Core'])
  await ui.unmount()
})

test('the unit-test scheme offers no "none": setup finds one itself when none is passed', async ($, on) => {
  await session($, on)
  await runCommand($, 'xcrew', 'setup')
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const unit = (await ui.find({ type: 'Select', key: 'test-scheme' }))?.props as { options: { value: string }[] }
  expect(unit.options.map(option => option.value)).toEqual(['App', 'Core'])
  await ui.unmount()
})

test('a form the session can\'t place says why, and names the skill', async ($, on) => {
  await session($, on, CHOICES, ['terminal'], false)
  const answer = await runCommand($, 'xcrew', 'setup')
  expect(answer).toMatchObject({ text: expect.stringContaining('the terminal is too narrow') })
  expect(answer).toMatchObject({ text: expect.stringContaining('/xcrew:setup') })
})

test('after a write the form reads the config it now has', async ($, on) => {
  await session($, on, CHOICES, ['terminal'], true, { ...CHOICES, config: { owner: 'xcrew', scheme: 'App' } })
  await runCommand($, 'xcrew', 'setup')
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.press({ key: 'write' })
  expect(await ui.find({ type: 'Text', text: /xcrew wrote the config; it builds App/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /wrote \.mobilebuildmcp\/config\.yaml/ })).toBeDefined()
  await ui.unmount()
})
