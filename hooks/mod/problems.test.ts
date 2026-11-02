import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Problem } from './cli'
import { RESTART_CHECK } from './problems'
import { runCommand, stubCli, submitPrompt } from './testing'

const BAND = {
  plugin: 'xcrew',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 100, scroll: { offset: 0, bodyRows: 10 }, view: {} },
} as const

const PIN: Problem = { status: 'warn', id: 'xcode/pin', message: 'The project pins Xcode 26.4, which isn\'t installed: xcodes install 26.4' }
const UNSIGNED: Problem = { status: 'warn', id: 'xcode-mcp/unsigned-agents-off', message: 'Xcode accepts unsigned agents: defaults write com.apple.dt.Xcode IDEAllowUnauthenticatedAgents -bool NO' }
const STALE: Problem = { status: 'warn', id: RESTART_CHECK, message: "the config changed after this session's MobileBuildMCP started: restart Claude Code to load it" }
const NOT_APPROVED: Problem = { status: 'fail', id: 'xcode-mcp/claude-approved', message: "Claude Code isn't approved in Xcode: call XcodeOpenWorkspace and approve it" }

/** Stands for the engine: the doctor prints `problems` whenever asked, and the band draws nothing of its own. */
function sessionWith(on: On, problems: Problem[], doctorFails = () => false) {
  const clock = mock.clock(on)
  mock.store(on)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.end', (_, e) => ({ sessionId: e.sessionId }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  const calls = stubCli(on, { problems, doctorFails })
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return Text({ children: ['engine'] })
  })
  on('tool.call', () => ({ result: {}, text: 'ok' }))
  on('prompt.submit', (_, e) => ({ text: e.text }))
  return { calls, clock }
}

test('a problem found at session start shows on the band, with where to look', async ($, on) => {
  const { calls, clock } = sessionWith(on, [PIN])
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()

  expect(calls.map(call => call.args)).toContainEqual(['doctor', '--problems', '--json'])
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: '⚠' }))?.props.color).toBe('warning')
  expect((await ui.find({ type: 'Text', text: /^The project pins Xcode 26.4/ }))?.props.color).toBe('warning')
  expect((await ui.find({ type: 'Text', text: /^\/xcrew doctor$/ }))?.props.color).toBeUndefined()
  await ui.unmount()
})

test('the band shows the doctor\'s first problem, which it lists worst first, and how many more there are', async ($, on) => {
  const { clock } = sessionWith(on, [NOT_APPROVED, PIN])
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: '⚠' }))?.props.color).toBe('error')
  expect((await ui.find({ type: 'Text', text: /^Claude Code isn't approved in Xcode/ }))?.text).toBe("Claude Code isn't approved in Xcode: call XcodeOpenWorkspace and approve it")
  expect((await ui.find({ type: 'Text', text: /^\(\+1 more\)$/ }))).toBeDefined()
  await ui.unmount()
})

test('with nothing wrong the band stays as it was', async ($, on) => {
  const { clock } = sessionWith(on, [])
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('engine')
  await ui.unmount()
})

test('while a run shows, it outranks a problem', async ($, on) => {
  const { clock } = sessionWith(on, [PIN])
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  await $.tool.call({ tool: 'mcp__xcode__BuildProject' } as never)
  await clock.advance(60_000)

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: '⚠' })).toBeUndefined()
  await ui.unmount()
})

// MARK: Keeping the band current

test('a warning leaves the band two minutes after it first shows, with nothing else happening', async ($, on) => {
  const { clock } = sessionWith(on, [PIN])
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  await clock.advance(119_000)
  expect(await ui.find({ type: 'Text', text: '⚠' })).toBeDefined()
  await clock.advance(2_000)
  expect(await ui.find({ type: 'Text', text: '⚠' })).toBeUndefined()
  await ui.unmount()
})

test('a failure stays until the doctor, run again, finds it fixed', async ($, on) => {
  const problems = [NOT_APPROVED]
  const { clock, calls } = sessionWith(on, problems)
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  await clock.advance(10 * 60_000)
  expect(await ui.find({ type: 'Text', text: /isn't approved/ })).toBeDefined()

  problems.splice(0)
  await submitPrompt($, 'build it')
  await clock.settle()
  expect(await ui.find({ type: 'Text', text: /isn't approved/ })).toBeDefined()
  const doctorRuns = () => calls.filter(call => call.args[0] === 'doctor').length
  const before = doctorRuns()
  await runCommand($, 'xcrew', 'doctor')
  await clock.settle()
  expect(await ui.find({ type: 'Text', text: /isn't approved/ })).toBeUndefined()
  // One run of the checks gives both the report and the band's problems.
  expect(doctorRuns() - before).toBe(1)
  await ui.unmount()
})

/** The doctor holds what xcrew needs to run, which a prompt doesn't change: it runs at session start, and again only when asked or after setup. */
test('a prompt never runs the doctor again', async ($, on) => {
  const { calls, clock } = sessionWith(on, [PIN])
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const doctorRuns = () => calls.filter(call => call.args[0] === 'doctor' && call.args.includes('--problems')).length
  expect(doctorRuns()).toBe(1)

  await submitPrompt($, 'one')
  await clock.advance(31_000)
  await submitPrompt($, 'two')
  await clock.advance(10 * 60_000)
  await submitPrompt($, 'three')
  await clock.settle()
  expect(doctorRuns()).toBe(1)
})

test('a warning found later shows for its own two minutes', async ($, on) => {
  const problems = [PIN]
  const { clock } = sessionWith(on, problems)
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  await clock.advance(3 * 60_000)

  problems.push(UNSIGNED)
  await runCommand($, 'xcrew', 'doctor')
  await clock.settle()
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /unsigned agents/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /pins Xcode 26.4/ })).toBeUndefined()
  await ui.unmount()
})

test('a doctor that couldn\'t run leaves the band as it was', async ($, on) => {
  let failing = false
  const { clock } = sessionWith(on, [NOT_APPROVED], () => failing)
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  failing = true
  await clock.advance(31_000)
  await submitPrompt($, 'while the CLI rebuilds')
  await clock.settle()
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /isn't approved/ })).toBeDefined()
  await ui.unmount()
})

test('a new session shows its warnings again', async ($, on) => {
  const { clock } = sessionWith(on, [PIN])
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  await clock.advance(3 * 60_000)
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: '⚠' })).toBeDefined()
  await ui.unmount()
})

test('a cleared conversation reads the doctor once, on its first prompt, and shows its warnings again', async ($, on) => {
  const { calls, clock } = sessionWith(on, [PIN])
  const doctorRuns = () => calls.filter(call => call.args[0] === 'doctor' && call.args.includes('--problems')).length
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  await clock.advance(3 * 60_000)

  await $.session.end({ reason: 'clear', sessionId: 'before', resume: { id: 'before' } })
  await clock.settle()
  expect(doctorRuns()).toBe(1)
  await submitPrompt($, 'first after the clear')
  await clock.settle()
  expect(doctorRuns()).toBe(2)
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: '⚠' })).toBeDefined()
  await ui.unmount()

  await submitPrompt($, 'second')
  await clock.settle()
  expect(doctorRuns()).toBe(2)
})

test('a session that ends another way reads nothing again', async ($, on) => {
  const { calls, clock } = sessionWith(on, [PIN])
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  await $.session.end({ reason: 'other', sessionId: 'before', resume: { id: 'before' } })
  await submitPrompt($, 'after')
  await clock.settle()
  expect(calls.filter(call => call.args[0] === 'doctor').length).toBe(1)
})

test('the doctor read names its session, so the CLI records the mod as loaded in it', async ($, on) => {
  const { calls, clock } = sessionWith(on, [PIN])
  on('session.id', () => ({ value: '5f0c1a2b-0000-4000-8000-000000000003' }))
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  expect(calls.map(call => call.args)).toContainEqual(['doctor', '--problems', '--json', '--session', '5f0c1a2b-0000-4000-8000-000000000003'])
})

test('a first doctor read that failed is tried once more, on the next prompt, and not again', async ($, on) => {
  const { calls, clock } = sessionWith(on, [PIN], () => true)
  const doctorRuns = () => calls.filter(call => call.args[0] === 'doctor').length
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const atStart = doctorRuns()
  await submitPrompt($, 'first')
  await clock.settle()
  const afterFirst = doctorRuns()
  expect(afterFirst).toBeGreaterThan(atStart)
  await submitPrompt($, 'second')
  await clock.settle()
  expect(doctorRuns()).toBe(afterFirst)
})

// MARK: The restart a changed config needs

test('a config MobileBuildMCP hasn\'t loaded outranks a failure, and stays past two minutes', async ($, on) => {
  const { clock } = sessionWith(on, [NOT_APPROVED, STALE])
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  await clock.advance(3 * 60_000)
  expect(await ui.find({ type: 'Text', text: /restart Claude Code to load it/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /isn't approved/ })).toBeUndefined()
  await ui.unmount()
})

test('the restart outranks a finished run', async ($, on) => {
  const { clock } = sessionWith(on, [STALE])
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  await $.tool.call({ tool: 'mcp__xcode__BuildProject' } as never)
  await clock.settle()
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /restart Claude Code to load it/ })).toBeDefined()
  await ui.unmount()
})

test('running xcrew setup reads the doctor again at once, whatever setup printed', async ($, on) => {
  const problems: Problem[] = []
  const { clock } = sessionWith(on, problems)
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  problems.push(STALE)
  await $.tool.call({ tool: 'Bash', command: '"/plugins/xcrew/bin/xcrew" setup --app-scheme App' } as never)
  await clock.settle()
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /restart Claude Code to load it/ })).toBeDefined()
  await ui.unmount()
})

test('after setup, a doctor read already in flight is followed by a fresh one', async ($, on) => {
  const problems: Problem[] = []
  const clock = mock.clock(on)
  mock.store(on)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return Text({ children: ['engine'] })
  })
  on('tool.call', () => ({ result: {}, text: 'ok' }))
  // The doctor started at session start is still running when setup writes; it answers with what it saw before.
  let doctorRuns = 0
  let began = () => {}
  const firstBegan = new Promise<void>(resolve => (began = resolve))
  let release = () => {}
  const released = new Promise<void>(resolve => (release = resolve))
  on('process.run', async (_, e) => {
    const args = e.argv.slice(1)
    if (args[0] === 'doctor') {
      doctorRuns += 1
      const seen = doctorRuns === 1 ? [] : [...problems]
      if (doctorRuns === 1) {
        began()
        await released
      }
      return { value: { exitCode: 0, stdout: JSON.stringify(seen), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    }
    const stdout = args[0] === '--binary-path' ? '/built/xcrew\n' : '{}'
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await firstBegan
  problems.push(STALE)
  await $.tool.call({ tool: 'Bash', command: 'xcrew setup' } as never)
  release()
  await clock.settle()
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /restart Claude Code to load it/ })).toBeDefined()
  await ui.unmount()
})

/** A doctor that can't run, as while the CLI builds, isn't run again: the report says so, and the band reads it next prompt. */
test('/xcrew doctor that gets no answer says so without running the checks again', async ($, on) => {
  let fails = false
  const { calls, clock } = sessionWith(on, [PIN], () => fails)
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  fails = true
  const before = calls.length
  const ran = await runCommand($, 'xcrew', 'doctor')
  expect(String(ran.text)).toContain("couldn't run")
  // The CLI's own wrapper may ask its shim once more; nothing runs the doctor in another form.
  const after = calls.slice(before).filter(call => call.args[0] === 'doctor')
  expect(after.length).toBeGreaterThan(0)
  expect(after.every(call => call.args.includes('--text-and-problems'))).toBe(true)
})
