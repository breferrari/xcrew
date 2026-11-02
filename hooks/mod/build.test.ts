import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'
import { BUILT_BINARY, callTool, stubCli } from './testing'

/** A session in a terminal, its CLI stubbed with `spawn` for the session start's background build. */
function session(on: On, spawn: { held?: Promise<void>; fails?: boolean; printsNothing?: boolean } = {}) {
  const clock = mock.clock(on)
  mock.store(on)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => ({ value: { tool: `mcp__xcrew__${e.name}` } }))
  on('session.surfaces', () => ({ value: ['vscode'] }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('tool.call', () => ({ result: {}, text: 'done' }))
  const cli = stubCli(on, { spawn })
  return { clock, cli }
}

async function start($: Engine) {
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
}

/**
 * After `/reload-plugins` no SessionStart command hook builds the CLI, but the mod's session start fires: it starts the
 * shim's cheapest command there, not waited on, which builds only when no build matches this version.
 */
test("a session start starts the shim's build without waiting for it", async ($, on) => {
  let release: () => void = () => {}
  const held = new Promise<void>(resolve => { release = resolve })
  const { clock, cli } = session(on, { held })
  await start($)
  expect(cli.filter(call => call.spawned).map(call => call.args)).toEqual([['--binary-path']])
  release()
  await clock.settle()
})

/**
 * The background build is dispatched first of the session start's calls on the shim, ahead of the doctor's read and
 * the rest, which run under time limits of their own, so it's the likeliest to take the shim's lock.
 */
test("the background build is dispatched first of the session start's calls on the shim", async ($, on) => {
  const { clock, cli } = session(on)
  await start($)
  await clock.settle()
  const shim = cli.filter(call => call.args[0] === '--binary-path')
  expect(shim[0]).toEqual({ args: ['--binary-path'], spawned: true })
  expect(shim.length).toBeGreaterThan(1)
})

/** With no build and a background build that can't start, a call builds through the shim as it did before. */
test("a background build that can't start leaves the first CLI call to build", async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => ({ value: { tool: `mcp__xcrew__${e.name}` } }))
  on('session.surfaces', () => ({ value: ['vscode'] }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('tool.call', () => ({ result: {}, text: 'done' }))
  const cli = stubCli(on, { built: () => false, spawn: { fails: true } })
  await start($)
  await clock.settle()
  await callTool($, 'mcp__xcode__BuildProject')
  await clock.settle()
  expect(cli.filter(call => call.args[0] === 'report').map(call => [call.program ?? 'the shim', call.ifBuilt ?? false])).toEqual([['the shim', false]])
})

/** A background build that ends naming no binary, as one killed or failed does, records nothing: calls keep the build they found. */
test('a background build that names no binary leaves the known build as it was', async ($, on) => {
  const { clock, cli } = session(on, { printsNothing: true })
  await start($)
  await clock.settle()
  await callTool($, 'mcp__xcode__BuildProject')
  await clock.settle()
  expect(cli.filter(call => call.args[0] === 'report').map(call => call.program ?? 'the shim')).toEqual([BUILT_BINARY])
})

/**
 * At a reload the background build is the only builder: a call made meanwhile asks the shim only whether a build is
 * there, starts none and stops none, and waits for it no longer than its own time, then answers without its note.
 */
test("a quick call during the background build doesn't build, doesn't stop it, and gives up in its own time", async ($, on) => {
  let finish: () => void = () => {}
  const held = new Promise<void>(resolve => { finish = resolve })
  let built = false
  const clock = mock.clock(on)
  mock.store(on)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => ({ value: { tool: `mcp__xcrew__${e.name}` } }))
  on('tool.describe', (_, e) => ({ description: e.description }))
  on('session.surfaces', () => ({ value: ['vscode'] }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('tool.call', () => ({ result: { ok: true } }))
  const cli = stubCli(on, { built: () => built, spawn: { held }, project: () => ({ isGenerated: true }) })
  await start($)
  const before = cli.length
  let answered = false
  const call = callTool($, 'mcp__xcode__XcodeWrite', { filePath: 'App/Info.plist', content: '' }).then(result => {
    answered = true
    return result
  })
  await clock.advance(9_000)
  expect(answered).toBe(false)
  await clock.advance(2_000)
  // Without the CLI's answer the edit goes through as the server takes it: the note it would have added is dropped.
  expect((await call).result).toEqual({ ok: true })
  expect(cli.filter(call => call.spawned)).toHaveLength(1)
  // Every call only asked whether a build is there, and none ran its command through the shim once its time was up.
  const asked = cli.slice(before).filter(call => !call.spawned)
  expect(asked.every(call => call.ifBuilt && call.args[0] === '--binary-path')).toBe(true)
  expect(asked.map(call => call.timeoutMs)).toContain(10_000)
  built = true
  finish()
  await clock.settle()
  // The build went on to its end, and the next call runs it.
  await callTool($, 'mcp__xcode__XcodeWrite', { filePath: 'App/Info.plist', content: '' })
  expect(cli.filter(call => call.args[0] === 'project').map(call => call.program ?? 'the shim')).toEqual([BUILT_BINARY])
})
