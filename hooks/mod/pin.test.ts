import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Report } from './cli'
import { callTool, stubCli } from './testing'

const PIN = "xcrew: builds use Xcode 27.2 while the project pins Xcode 26.5 (.xcode-version): a different SDK may be the cause. To build with the pin, xcodes install 26.5"
const FAILED: Partial<Report> = { ok: false, detail: 'build failed', failures: [{ title: 'App.swift:2', message: 'module compiled with Swift 6.1 cannot be imported by the Swift 6.3 compiler' }], notes: [], pinNote: PIN, pin: '26.5 (.xcode-version)' }

function session(on: On, reports: Partial<Report>[]) {
  mock.clock(on)
  mock.store(on)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => ({ value: { tool: `mcp__xcrew__${e.name}` } }))
  stubCli(on, { reports })
  on('tool.call', () => ({ result: {}, text: 'the server\'s result' }))
}

const build = async ($: Parameters<typeof callTool>[0]) => ((await callTool($, 'mcp__MobileBuildMCP__build_sim')).context ?? []) as string[]

test('the pin is named with the first failure it may explain, and not again in the session', async ($, on) => {
  session(on, [FAILED, FAILED])
  expect(await build($)).toContain(PIN)
  expect(await build($)).not.toContain(PIN)
})

test('another pin, or a new session, is named again', async ($, on) => {
  const other = PIN.replaceAll('26.5', '26.4')
  session(on, [FAILED, { ...FAILED, pinNote: other, pin: '26.4 (.xcode-version)' }, FAILED])
  await build($)
  expect(await build($)).toContain(other)
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  expect(await build($)).toContain(PIN)
})

test('a pin is named once a session, though its note words it another way', async ($, on) => {
  const restart = "xcrew: MobileBuildMCP started without the project's pin, Xcode 26.5 (.xcode-version), so it builds with Xcode 27.2: a different SDK may be the cause. Restart Claude Code to build with the pin."
  session(on, [FAILED, { ...FAILED, pinNote: restart }])
  expect(await build($)).toContain(PIN)
  expect(await build($)).not.toContain(restart)
})
