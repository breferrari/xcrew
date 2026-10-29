import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import { BUILT_BINARY, callTool, stubCli, type CliCall } from './testing'

const MALFORMED =
  "External macro implementation type 'MockableMacros.MockableMacro' could not be found; plugin for module 'MockableMacros' produced malformed response"

type Seen = { toasts: string[]; statuses: (string | undefined)[]; cli: CliCall[] }

/** Records what the mod shows and asks the CLI; `cli` is how the stand-in CLI answers. */
function watch(on: On, stored: Record<string, unknown> = {}, cli: Parameters<typeof stubCli>[1] = {}): Seen {
  const seen: Seen = { toasts: [], statuses: [], cli: stubCli(on, cli) }
  mock.store(on, stored)
  on('ui.toast', (_, e) => {
    seen.toasts.push(e.text)
    return { value: undefined }
  })
  on('ui.status', (_, e) => {
    seen.statuses.push(e.text)
    return { value: undefined }
  })
  return seen
}

// MARK: The project-file guard

/** A project the CLI calls generated or not; the engine beneath answers tool descriptions as written. */
function projectThatIs(on: On, generated: 'generated' | 'classic') {
  on('tool.describe', (_, e) => ({ description: e.description }))
  return stubCli(on, { project: { isGenerated: generated === 'generated' } })
}

test('in a generated project XcodeWrite is refused under either registration, with the alternative named', async ($, on) => {
  const asked = projectThatIs(on, 'generated')
  on('tool.call', () => ({ result: {} }))
  for (const tool of ['mcp__xcode__XcodeWrite', 'mcp__plugin_xcrew_xcode__XcodeWrite']) {
    const ran = await callTool($, tool, { filePath: 'App/New.swift', content: '' })
    expect(ran.deny).toContain('Write tool')
  }
  // Whether a project is generated is the CLI's to say, from the manifests wherever they sit.
  expect(asked.map(call => call.args)).toContainEqual(['project'])
})

test('when the CLI can\'t say, XcodeWrite is let through: refusing it would block a classic project', async ($, on) => {
  on('process.run', () => {
    throw new Error('xcrew not built')
  })
  on('tool.call', () => ({ result: { ok: true } }))
  const ran = await callTool($, 'mcp__xcode__XcodeWrite', { filePath: 'a', content: '' })
  expect(ran.deny).toBeUndefined()
})

test('in a classic Xcode project XcodeWrite works, since it is how a file joins its target there', async ($, on) => {
  projectThatIs(on, 'classic')
  on('tool.call', () => ({ result: { ok: true } }))
  const ran = await callTool($, 'mcp__xcode__XcodeWrite', { filePath: 'a', content: '' })
  expect(ran.deny).toBeUndefined()
})

test('in a generated project XcodeWrite\'s description says to use Write, so Claude does not try it first', async ($, on) => {
  projectThatIs(on, 'generated')
  const described = await $.tool.describe({ tool: 'mcp__plugin_xcrew_xcode__XcodeWrite', description: 'Writes a file.', provider: { plugin: 'xcrew', tier: 'user' } })
  expect(described.description).toMatch(/^Writes a file\.\n\n.*generated.*Write tool/s)
})

test('in a classic Xcode project XcodeWrite\'s description is left as the server wrote it', async ($, on) => {
  projectThatIs(on, 'classic')
  const described = await $.tool.describe({ tool: 'mcp__xcode__XcodeWrite', description: 'Writes a file.', provider: { plugin: 'xcrew', tier: 'user' } })
  expect(described.description).toBe('Writes a file.')
})

test('other Xcode file tools pass', async ($, on) => {
  on('tool.call', () => ({ result: { ok: true } }))
  const ran = await callTool($, 'mcp__xcode__XcodeUpdate', { filePath: 'a', oldString: 'x', newString: 'y' })
  expect(ran.isError).toBeUndefined()
})

// MARK: Handing the result to the CLI

test('a finished run hands the server\'s text to the CLI, saying which server and kind of run', async ($, on) => {
  mock.clock(on)
  const seen = watch(on)
  on('tool.call', () => ({ result: {}, isError: true, text: MALFORMED }))

  await callTool($, 'mcp__xcode__BuildProject')

  expect(seen.cli.filter(call => call.args[0] !== '--binary-path').map(({ args, stdin, program }) => ({ args, stdin, program }))).toEqual([{ args: ['report', '--server', 'xcode', '--kind', 'build', '--error'], stdin: MALFORMED, program: BUILT_BINARY }])
})

test('a build failing on a killed macro plugin reaches Claude as the server reported it, with nothing retried', async ($, on) => {
  mock.clock(on)
  watch(on, {}, { reports: [{ ok: false }] })
  let calls = 0
  on('tool.call', () => {
    calls += 1
    return { result: {}, isError: true, text: MALFORMED }
  })

  const ran = await callTool($, 'mcp__xcode__BuildProject')

  expect(calls).toBe(1)
  expect(ran.text).toBe(MALFORMED)
})

test('when the CLI has a shorter result, Claude reads that one, still marked as an error', async ($, on) => {
  mock.clock(on)
  watch(on, {}, { reports: [{ ok: false, detail: '1 of 41 failed', result: 'the short version', notes: ['a note'] }] })
  on('tool.call', () => ({ result: {}, isError: true, text: 'the long version' }))

  const ran = await callTool($, 'mcp__MobileBuildMCP__test_sim')

  // Core uses its own messages for the call while `ref` is kept, so the mod answers with its own `result`.
  expect(ran.ref).toBeUndefined()
  expect(ran.result).toBe('the short version')
  expect(ran.isError).toBe(true)
  expect(ran.context).toEqual(['a note'])
})

test('the CLI\'s notes reach Claude beside a result it left alone', async ($, on) => {
  mock.clock(on)
  const seen = watch(on, {}, { reports: [{ ok: false, detail: 'no tests ran', notes: ['xcrew: this test run ran no tests'] }] })
  on('tool.call', () => ({ result: {}, text: 'SUCCEEDED' }))

  const ran = await callTool($, 'mcp__MobileBuildMCP__test_sim', { extraArgs: ['-only-testing:Nope'] })

  expect(ran.text).toBe('SUCCEEDED')
  expect(ran.context).toEqual(['xcrew: this test run ran no tests'])
  expect(seen.toasts).toEqual(['✗ test_sim · 0:00 · no tests ran'])
})

test('without the CLI, the outcome is whether the server reported an error', async ($, on) => {
  mock.clock(on)
  mock.store(on)
  const toasts: string[] = []
  on('ui.toast', (_, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  on('ui.status', () => ({ value: undefined }))
  on('process.run', () => {
    throw new Error('xcrew not built')
  })
  on('tool.call', () => ({ result: {}, isError: true, text: 'failed' }))

  const ran = await callTool($, 'mcp__MobileBuildMCP__build_sim')

  expect(toasts).toEqual(['✗ build_sim · 0:00'])
  expect(ran.text).toBe('failed')
})

// MARK: Build and test timing

test('a build shows its elapsed time while it runs and a toast when it ends', async ($, on) => {
  const clock = mock.clock(on)
  const seen = watch(on)
  on('tool.call', async () => {
    await clock.advance(3_000)
    expect(seen.statuses.at(-1)).toBe('build_sim running · 0:03')
    await clock.advance(69_000)
    return { result: {}, text: 'Build succeeded' }
  })

  await callTool($, 'mcp__plugin_xcrew_MobileBuildMCP__build_sim')

  expect(seen.statuses.at(-1)).toBeUndefined()
  expect(seen.toasts).toEqual(['✓ build_sim · 1:12'])
})

test('a failed test run says so', async ($, on) => {
  mock.clock(on)
  const seen = watch(on)
  on('tool.call', () => ({ result: {}, isError: true, text: '2 tests failed' }))
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  expect(seen.toasts).toEqual(['✗ test_sim · 0:00'])
})

test('later runs compare with the average of earlier ones', async ($, on) => {
  const clock = mock.clock(on)
  const seen = watch(on)
  const durations = [60_000, 80_000, 90_000]
  on('tool.call', async () => {
    await clock.advance(durations.shift() ?? 0)
    return { result: {}, text: 'ok' }
  })

  for (let run = 0; run < 3; run += 1) {
    await callTool($, 'mcp__xcode__BuildProject')
  }

  expect(seen.toasts).toEqual(['✓ BuildProject · 1:00', '✓ BuildProject · 1:20 (avg 1:00)', '✓ BuildProject · 1:30 (avg 1:10)'])
})

test('a run far slower than usual says how much slower', async ($, on) => {
  const clock = mock.clock(on)
  const seen = watch(on, { 'durations.build_sim': [11_000, 11_000, 11_000, 11_000, 11_000] })
  on('tool.call', async () => {
    await clock.advance(22_000)
    return { result: {}, text: 'ok' }
  })

  await callTool($, 'mcp__MobileBuildMCP__build_sim')

  expect(seen.toasts).toEqual(['✓ build_sim · 0:22 (2× its usual 0:11)'])
})

test('slowness is only called out once there are five earlier runs to judge by', async ($, on) => {
  const clock = mock.clock(on)
  const seen = watch(on, { 'durations.BuildProject': [10_000, 10_000, 10_000, 10_000] })
  on('tool.call', async () => {
    await clock.advance(30_000)
    return { result: {}, text: 'ok' }
  })

  await callTool($, 'mcp__xcode__BuildProject')

  expect(seen.toasts).toEqual(['✓ BuildProject · 0:30 (avg 0:10)'])
})

test('a run is timed by what the server reports, so a pre-build hook or a permission prompt is left out', async ($, on) => {
  const clock = mock.clock(on)
  const seen = watch(on, {}, { reports: [{ ok: true, detail: '3 passed', durationMs: 15_000 }] })
  on('tool.call', async () => {
    await clock.advance(40_000)
    return { result: {}, text: 'ok' }
  })

  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  await callTool($, 'mcp__MobileBuildMCP__test_sim')

  expect(seen.toasts).toEqual(['✓ test_sim · 0:15 · 3 passed', '✓ test_sim · 0:15 (avg 0:15) · 3 passed'])
})

// MARK: Live phase

const LOG = '/Users/dev/Library/Developer/MobileBuildMCP/workspaces/App-0000/logs/test_sim_1.log'

test('while a MobileBuildMCP run goes, the status line says what the CLI reads from its log', async ($, on) => {
  const clock = mock.clock(on)
  const seen = watch(on, { 'tests.test_sim': 959 }, { phase: () => ({ log: LOG, phase: 'testing 2 of 959' }) })
  on('tool.call', async () => {
    await clock.advance(3_000)
    return { result: {}, text: 'ok' }
  })

  await callTool($, 'mcp__MobileBuildMCP__test_sim')

  expect(seen.statuses).toContain('test_sim running · 0:03 · testing 2 of 959')
  const asked = seen.cli.filter(call => call.args[0] === 'phase').map(call => call.args)
  expect(asked[0]).toEqual(['phase', '--tool', 'test_sim', '--since', '0', '--expected', '959'])
  // Once found, the log is passed back, which saves the CLI looking again.
  expect(asked.at(-1)).toEqual(['phase', '--tool', 'test_sim', '--since', '0', '--expected', '959', '--log', LOG])
})

test('a test run remembers how many tests it ran, for the next run\'s count', async ($, on) => {
  const clock = mock.clock(on)
  const seen = watch(on, {}, { reports: [{ ok: true, tests: 3 }], phase: () => ({ log: LOG }) })
  on('tool.call', async () => {
    await clock.advance(2_000)
    return { result: {}, text: 'ok' }
  })

  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  await callTool($, 'mcp__MobileBuildMCP__test_sim')

  expect(seen.cli.filter(call => call.args[0] === 'phase').at(-1)?.args).toContain('3')
})

test('a tool that has written a log before says it is preparing until this run\'s log appears', async ($, on) => {
  const clock = mock.clock(on)
  const seen = watch(on, { 'logs.test_sim': true })
  on('tool.call', async () => {
    await clock.advance(3_000)
    return { result: {}, text: 'ok' }
  })

  await callTool($, 'mcp__MobileBuildMCP__test_sim')

  expect(seen.statuses).toContain('test_sim running · 0:03 · preparing')
})

test('a tool that never writes a log, like clean, shows just its time', async ($, on) => {
  const clock = mock.clock(on)
  const seen = watch(on)
  on('tool.call', async () => {
    await clock.advance(3_000)
    return { result: {}, text: 'cleaned' }
  })

  await callTool($, 'mcp__MobileBuildMCP__clean')

  expect(seen.statuses).toContain('clean running · 0:03')
  expect(seen.statuses.some(status => status?.includes('preparing'))).toBe(false)
})

test('finding a run\'s log teaches the mod that the tool writes one', async ($, on) => {
  const clock = mock.clock(on)
  const disk = { hasLog: true }
  const seen = watch(on, {}, { phase: () => (disk.hasLog ? { log: LOG } : {}) })
  on('tool.call', async () => {
    await clock.advance(2_000)
    return { result: {}, text: 'ok' }
  })
  await callTool($, 'mcp__MobileBuildMCP__test_sim')
  disk.hasLog = false

  await callTool($, 'mcp__MobileBuildMCP__test_sim')

  expect(seen.statuses.some(status => status?.startsWith('test_sim running · 0:02') && status.endsWith(' · preparing'))).toBe(true)
})

test('Xcode MCP runs ask for no phase: that server writes no log to follow', async ($, on) => {
  const clock = mock.clock(on)
  const seen = watch(on)
  on('tool.call', async () => {
    await clock.advance(3_000)
    return { result: {}, text: 'ok' }
  })

  await callTool($, 'mcp__xcode__BuildProject')

  expect(seen.cli.map(call => call.args[0]).filter(command => command !== '--binary-path')).toEqual(['report'])
})

test('where no band draws, the status line carries the gauge against the usual time', async ($, on) => {
  const clock = mock.clock(on)
  const seen = watch(on, { 'durations.BuildProject': [36_000] })
  on('tool.call', async () => {
    await clock.advance(21_000)
    return { result: {}, text: 'ok' }
  })

  await callTool($, 'mcp__xcode__BuildProject')

  expect(seen.statuses).toContain('BuildProject running · 0:21 ━━━━╸─── ~0:15 left')
})

test('the usual time is kept per scheme, so a small module is not measured against the whole app', async ($, on) => {
  const clock = mock.clock(on)
  const seen = watch(on, { 'durations.build_sim · Small': [10_000], 'durations.build_sim · Big': [600_000] })
  on('tool.call', async () => {
    await clock.advance(5_000)
    return { result: {}, text: 'ok' }
  })

  await callTool($, 'mcp__MobileBuildMCP__build_sim', { scheme: 'Small' })

  expect(seen.statuses).toContain('build_sim · Small · 0:05 ━━━━──── ~0:05 left')
})

test('a test run is also kept apart by the tests it selects', async ($, on) => {
  const clock = mock.clock(on)
  const seen = watch(on, { 'durations.test_sim · App › SmallTests': [10_000], 'durations.test_sim · App': [600_000] })
  on('tool.call', async () => {
    await clock.advance(5_000)
    return { result: {}, text: 'ok' }
  })

  await callTool($, 'mcp__MobileBuildMCP__test_sim', { scheme: 'App', extraArgs: ['-only-testing:SmallTests'] })

  expect(seen.statuses).toContain('test_sim · App · 0:05 ━━━━──── ~0:05 left')
})

test('a MobileBuildMCP run is measured from when its log appears, so a pre-build hook is not counted against its usual time', async ($, on) => {
  const clock = mock.clock(on)
  const disk = { hasLog: false }
  const seen = watch(on, { 'durations.test_sim': [36_000], 'logs.test_sim': true }, { phase: () => (disk.hasLog ? { log: LOG, phase: 'testing · 2 done' } : {}) })
  on('tool.call', async () => {
    await clock.advance(20_000)
    disk.hasLog = true
    await clock.advance(21_000)
    return { result: {}, text: 'ok' }
  })

  await callTool($, 'mcp__MobileBuildMCP__test_sim')

  expect(seen.statuses).toContain('test_sim running · 0:10 · preparing')
  // The log is found on the first tick after it appears, at 0:21, so by 0:41 the run has gone 20 s of its usual 36.
  expect(seen.statuses).toContain('test_sim running · 0:41 ━━━━╸─── ~0:16 left · testing · 2 done')
})

test('tools that neither build, test nor run are not timed', async ($, on) => {
  mock.clock(on)
  const seen = watch(on)
  on('tool.call', () => ({ result: {}, text: 'contents' }))
  await callTool($, 'mcp__xcode__XcodeRead', { filePath: 'a' })
  await callTool($, 'mcp__MobileBuildMCP__list_schemes')
  await callTool($, 'Bash', { command: 'ls' })
  expect(seen.toasts).toEqual([])
  expect(seen.statuses).toEqual([])
})

test('timing that fails never blocks the build', async ($, on) => {
  // No clock or store beneath: every bookkeeping call fails.
  let calls = 0
  on('tool.call', () => {
    calls += 1
    return { result: {}, text: 'Build succeeded' }
  })
  const ran = await callTool($, 'mcp__xcode__BuildProject')
  expect(calls).toBe(1)
  expect(ran.text).toBe('Build succeeded')
})

// MARK: Long runs

test('a run of a minute or more sends a notification with its outcome', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  const notifications: string[] = []
  on('ui.toast', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.notify', (_, e) => {
    notifications.push(e.text)
    return { value: { isSent: true, channel: 'terminal_bell' } }
  })
  on('tool.call', async () => {
    await clock.advance(61_000)
    return { result: {}, text: 'ok' }
  })
  stubCli(on, { reports: [{ ok: true, detail: '5 passed' }] })

  await callTool($, 'mcp__xcode__RunAllTests')

  expect(notifications).toEqual(['✓ RunAllTests · 1:01 · 5 passed'])
})

test('a shorter run does not notify', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  const notifications: string[] = []
  on('ui.toast', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.notify', (_, e) => {
    notifications.push(e.text)
    return { value: { isSent: true, channel: 'terminal_bell' } }
  })
  on('tool.call', async () => {
    await clock.advance(59_000)
    return { result: {}, text: 'ok' }
  })

  await callTool($, 'mcp__xcode__BuildProject')

  expect(notifications).toEqual([])
})

test('a notification that cannot be sent never affects the run', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  on('ui.toast', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.notify', () => {
    throw new Error('no channel')
  })
  on('tool.call', async () => {
    await clock.advance(90_000)
    return { result: {}, text: 'Build succeeded' }
  })

  const ran = await callTool($, 'mcp__xcode__BuildProject')

  expect(ran.text).toBe('Build succeeded')
})

// MARK: What's building

import * as captured from './fixtures'

/** Answers each call with the next captured result, and records the status line. */
function serve(on: On, results: Record<string, { isError: boolean; text: string }>, clock: { advance: (ms: number) => Promise<void> }) {
  const statuses: (string | undefined)[] = []
  on('ui.status', (_, e) => {
    statuses.push(e.text)
    return { value: undefined }
  })
  on('ui.toast', () => ({ value: undefined }))
  on('tool.call', async (_, e) => {
    const answer = results[e.tool.split('__').pop() ?? '']
    if (/build|test/i.test(e.tool)) await clock.advance(3_000)
    return { result: {}, text: answer?.text ?? 'ok', ...(answer?.isError ? { isError: true } : {}) }
  })
  return statuses
}

test('the status line names the scheme and simulator MobileBuildMCP will use', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  const statuses = serve(on, { session_show_defaults: captured.mobileSessionDefaults }, clock)

  await callTool($, 'mcp__plugin_xcrew_MobileBuildMCP__session_show_defaults')
  await callTool($, 'mcp__plugin_xcrew_MobileBuildMCP__test_sim')

  expect(statuses).toContain('test_sim · MacroProbe-Package on iPhone 16 · 0:03')
})

test('switching profiles changes what the status line names', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  const statuses = serve(on, { session_show_defaults: captured.mobileSessionDefaults, session_use_defaults_profile: captured.mobileProfileSwitched }, clock)

  await callTool($, 'mcp__MobileBuildMCP__session_show_defaults')
  await callTool($, 'mcp__MobileBuildMCP__session_use_defaults_profile', { profile: 'unit' })
  await callTool($, 'mcp__MobileBuildMCP__build_sim')

  expect(statuses).toContain('build_sim · iPhone 12 · 0:03')
})

test('the status line names the scheme and destination the Xcode MCP has active', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  const statuses = serve(on, { XcodeOpenWorkspace: captured.xcodeWorkspaceOpened }, clock)

  await callTool($, 'mcp__xcode__XcodeOpenWorkspace', { path: '/Users/dev/MacroProbe' })
  await callTool($, 'mcp__xcode__BuildProject')

  expect(statuses).toContain('BuildProject · MacroProbe-Package on My Mac · 0:03')
})

test('with nothing learned yet, the status line stays as it was', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  const statuses = serve(on, {}, clock)
  await callTool($, 'mcp__MobileBuildMCP__build_sim')
  expect(statuses).toContain('build_sim running · 0:03')
})

test('switching the Xcode MCP\'s scheme changes what the status line names', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  const statuses = serve(on, { XcodeOpenWorkspace: captured.xcodeWorkspaceOpened, XcodeSwitchScheme: captured.xcodeSchemeSwitched }, clock)

  await callTool($, 'mcp__xcode__XcodeOpenWorkspace', { path: '/Users/dev/MacroProbe' })
  await callTool($, 'mcp__xcode__XcodeSwitchScheme', { schemeName: 'MacroProbe' })
  await callTool($, 'mcp__xcode__BuildProject')

  expect(statuses).toContain('BuildProject · MacroProbe on iPhone 18 Pro · 0:03')
})

test('only the answers that name a scheme are read for one: a file that happens to hold one changes nothing', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  const statuses = serve(on, { XcodeRead: { isError: false, text: '{"activeScheme":"NotTheScheme"}' } }, clock)

  await callTool($, 'mcp__xcode__XcodeRead', { filePath: 'config.json' })
  await callTool($, 'mcp__xcode__BuildProject')

  expect(statuses).toContain('BuildProject running · 0:03')
})

test('a call the person denies leaves no trace: no time in the history, no outcome, no notification', async ($, on) => {
  const clock = mock.clock(on)
  const seen = watch(on, { 'durations.build_sim': [90_000] })
  const notifications: string[] = []
  on('ui.notify', (_, e) => {
    notifications.push(e.text)
    return { value: { isSent: true, channel: 'terminal_bell' } }
  })
  const answers: ({ deny: string } | { result: object; text: string })[] = [{ deny: 'The person denied this call.' }, { result: {}, text: 'ok' }]
  on('tool.call', async () => {
    const answer = answers.shift()!
    await clock.advance('deny' in answer ? 2_000 : 90_000)
    return answer
  })

  await callTool($, 'mcp__MobileBuildMCP__build_sim')
  // The next run is still measured against the usual 1:30, not an average the denied 0:02 pulled down.
  await callTool($, 'mcp__MobileBuildMCP__build_sim')

  expect(seen.toasts).toEqual(['✓ build_sim · 1:30 (avg 1:30)'])
  expect(notifications).toEqual(['✓ build_sim · 1:30 (avg 1:30)'])
  expect(seen.cli.filter(call => call.args[0] === 'report').length).toBe(1)
})

test('any session-defaults answer that names the profile in use is read, not only the ones listed', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  const statuses = serve(on, {
    session_show_defaults: captured.mobileSessionDefaults,
    session_clear_defaults: { isError: false, text: '{"schema":"mobilebuildmcp.output.session-profile","data":{"currentProfile":"unit"}}' },
  }, clock)

  await callTool($, 'mcp__MobileBuildMCP__session_show_defaults')
  await callTool($, 'mcp__MobileBuildMCP__session_clear_defaults')
  await callTool($, 'mcp__MobileBuildMCP__build_sim')

  expect(statuses).toContain('build_sim · iPhone 12 · 0:03')
})

test('the mod asks the shim for its build once, then runs the build directly', async ($, on) => {
  const clock = mock.clock(on)
  const seen = watch(on, {}, { phase: () => ({ log: LOG, phase: 'compiling App' }) })
  on('tool.call', async () => {
    await clock.advance(5_000)
    return { result: {}, text: 'ok' }
  })

  await callTool($, 'mcp__MobileBuildMCP__build_sim')
  await callTool($, 'mcp__MobileBuildMCP__build_sim')

  expect(seen.cli.filter(call => call.args[0] === '--binary-path')).toHaveLength(1)
  const direct = seen.cli.filter(call => call.args[0] !== '--binary-path')
  expect(direct.length).toBeGreaterThan(5)
  expect(direct.every(call => call.program === BUILT_BINARY)).toBe(true)
})

test('the build is asked for again after 30 s, so a development checkout\'s rebuild is picked up', async ($, on) => {
  const clock = mock.clock(on)
  const seen = watch(on)
  on('tool.call', async () => {
    await clock.advance(31_000)
    return { result: {}, text: 'ok' }
  })

  await callTool($, 'mcp__xcode__BuildProject')
  await callTool($, 'mcp__xcode__BuildProject')

  expect(seen.cli.filter(call => call.args[0] === '--binary-path')).toHaveLength(2)
})

test('when the shim names no build, the CLI runs through the shim', async ($, on) => {
  mock.clock(on)
  const seen = watch(on, {}, { noBuild: true })
  on('tool.call', () => ({ result: {}, text: 'ok' }))

  await callTool($, 'mcp__xcode__BuildProject')

  const report = seen.cli.find(call => call.args[0] === 'report')
  expect(report?.program).toBeUndefined()
})

test('a command that runs past its time is not run a second time through the shim', async ($, on) => {
  const clock = mock.clock(on)
  const seen = watch(on, {}, { build: { fails: 'by timing out', clock } })
  on('tool.call', () => ({ result: {}, text: 'ok' }))

  await callTool($, 'mcp__xcode__BuildProject')

  expect(seen.cli.filter(call => call.args[0] === 'report')).toHaveLength(1)
})

test('a build that can\'t be started falls back to the shim', async ($, on) => {
  mock.clock(on)
  const seen = watch(on, {}, { build: { fails: 'to start' } })
  on('tool.call', () => ({ result: {}, text: 'ok' }))

  await callTool($, 'mcp__xcode__BuildProject')

  const reports = seen.cli.filter(call => call.args[0] === 'report')
  expect(reports.map(call => call.program)).toEqual([BUILT_BINARY, undefined])
})

test('asking which build to run takes no longer than the caller allows', async ($, on) => {
  mock.clock(on)
  mock.store(on)
  const seen = projectThatIs(on, 'classic')
  on('tool.call', () => ({ result: { ok: true } }))

  await callTool($, 'mcp__xcode__XcodeWrite', { filePath: 'a', content: '' })

  expect(seen.find(call => call.args[0] === '--binary-path')?.timeoutMs).toBe(10_000)
})

test('callers at once share one question to the shim, and a build it can\'t name is remembered too', async ($, on) => {
  mock.clock(on)
  mock.store(on)
  on('tool.describe', (_, e) => ({ description: e.description }))
  const seen = stubCli(on, { noBuild: true })
  on('tool.call', () => ({ result: { ok: true } }))

  await Promise.all([1, 2, 3].map(() => callTool($, 'mcp__xcode__XcodeWrite', { filePath: 'a', content: '' })))
  await callTool($, 'mcp__xcode__XcodeWrite', { filePath: 'b', content: '' })

  expect(seen.filter(call => call.args[0] === '--binary-path')).toHaveLength(1)
  expect(seen.filter(call => call.args[0] === 'project')).toHaveLength(4)
})
