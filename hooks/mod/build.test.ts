import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'
import { BUILT_BINARY, callTool, runCommand, stubCli } from './testing'

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
 * the rest, so it's the likeliest to take the shim's lock.
 */
test("the background build is dispatched first of the session start's calls on the shim", async ($, on) => {
  const { clock, cli } = session(on)
  await start($)
  await clock.settle()
  const shim = cli.filter(call => call.args[0] === '--binary-path')
  expect(shim[0]).toEqual({ args: ['--binary-path'], spawned: true })
  expect(shim.length).toBeGreaterThan(1)
})

/** With no build and a background build that can't start, a call runs through the shim, which builds. */
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
  const cli = stubCli(on, { spawn: { fails: true } })
  await start($)
  await clock.settle()
  await callTool($, 'mcp__xcode__BuildProject')
  await clock.settle()
  expect(cli.filter(call => call.args[0] === 'report').map(call => call.program ?? 'the shim')).toEqual(['the shim'])
})

/** A background build that failed is remembered with why: a call says so and asks the shim for nothing more. */
test('a background build that failed is said by the calls after it, which build nothing again', async ($, on) => {
  const { clock, cli } = session(on, { printsNothing: true })
  await start($)
  await clock.settle()
  // The session start's own reads may each ask, as they go at once; the shim's lock keeps them to one build.
  const asked = cli.filter(call => call.args[0] === '--binary-path').length
  const result = await callTool($, 'mcp__xcode__BuildProject')
  await clock.settle()
  expect(cli.filter(call => call.args[0] === 'report')).toEqual([])
  expect(cli.filter(call => call.args[0] === '--binary-path')).toHaveLength(asked)
  expect(String(result.context ?? '')).toContain("its CLI couldn't be built for this version: Sources/xcrew/main.swift:1:1: error: cannot find 'x' in scope")
})

/**
 * At a reload the background build runs to its end: a call made meanwhile asks the shim for the build, which waits for
 * it through the shim's lock, however long it takes, and answers whole.
 */
test('a call during the background build waits for it through the shim and answers whole', async ($, on) => {
  let finish: () => void = () => {}
  const held = new Promise<void>(resolve => { finish = resolve })
  const clock = mock.clock(on)
  mock.store(on)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => ({ value: { tool: `mcp__xcrew__${e.name}` } }))
  on('session.surfaces', () => ({ value: ['vscode'] }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.invalidate', () => ({ value: undefined }))
  const cli = stubCli(on, { spawn: { held }, affected: () => ({ base: 'origin/main, from 0123456789ab', changed: [], selections: [] }), problems: [] })
  await start($)
  const affected = callTool($, 'mcp__xcrew__affected')
  const doctor = runCommand($, 'xcrew', 'doctor')
  // Past any time an older xcrew gave a call, the build still going.
  await clock.advance(11_000)
  finish()
  expect(String((await affected).result)).toStartWith('Nothing has changed')
  expect(String((await doctor).text)).toBe("the doctor's report")
  // The wait went through the shim's own build, spawned.
  expect(cli.filter(call => call.args[0] === '--binary-path').every(call => call.spawned)).toBe(true)
})

/** Every CLI call runs to its end: each is spawned, none run under a time of xcrew's or the API's. */
test('every CLI call is spawned, none given a time', async ($, on) => {
  mock.clock(on)
  mock.store(on)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => ({ value: { tool: `mcp__xcrew__${e.name}` } }))
  on('session.surfaces', () => ({ value: ['vscode'] }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('tool.call', () => ({ result: {}, text: 'done' }))
  const cli = stubCli(on, { affected: () => null })
  await callTool($, 'mcp__xcode__BuildProject')
  await callTool($, 'mcp__xcrew__affected')
  expect(cli.filter(call => ['report', 'affected'].includes(call.args[0] ?? '')).length).toBe(2)
  expect(cli.every(call => call.spawned)).toBe(true)
})
