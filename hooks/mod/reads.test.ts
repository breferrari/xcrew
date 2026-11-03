import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Problem, Report } from './cli'
import { readKey, readLine } from './cli'
import { AFFECTED_TOOL_NAME } from './affected'
import { EVIDENCE_TOOL_NAME } from './evidence'
import { LEDGER_TOOL_NAME } from './ledger'
import { LOOK_TOOL_NAME } from './look'
import { SAYS_FAILED_READS } from './tools'
import { callTool, runCommand, stubCli, submitPrompt } from './testing'

const PBXPROJ = '/work/App/ios/App.xcodeproj/project.pbxproj'
const editPbxproj = { file_path: PBXPROJ, old_string: 'a', new_string: 'b' }

const BAND = {
  plugin: 'xcrew',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 100, scroll: { offset: 0, bodyRows: 10 }, view: {} },
} as const

const PIN: Problem = { status: 'warn', id: 'xcode/pin', message: 'The project pins Xcode 26.4, which isn\'t installed: xcodes install 26.4' }

/** A session whose tools answer, with the CLI stubbed by `answers`. */
function session(on: On, answers: Parameters<typeof stubCli>[1] = {}) {
  const clock = mock.clock(on)
  mock.store(on)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.end', (_, e) => ({ sessionId: e.sessionId }))
  on('session.cwd', () => ({ value: '/work/App' }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => ({ value: { tool: `mcp__xcrew__${e.name}` } }))
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return Text({ children: ['engine'] })
  })
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('tool.call', () => ({ result: {}, text: 'done' }))
  return { clock, cli: stubCli(on, answers) }
}

test('a read before an edit that the CLI couldn\'t answer says so on the edit\'s result', async ($, on) => {
  session(on, {
    project: args => {
      if (args.includes('--generated')) throw new Error('spawn ENOENT')
      return { isGenerated: true }
    },
  })
  const edited = await callTool($, 'Edit', editPbxproj)
  expect(edited.deny).toBeUndefined()
  expect((edited.context ?? []).some(line => line.startsWith(`xcrew project --generated ${PBXPROJ} couldn't run: `))).toBe(true)
})

test('a run whose report the CLI couldn\'t read says so on its result', async ($, on) => {
  session(on, { reportFails: () => true })
  const result = await callTool($, 'mcp__xcode__BuildProject')
  expect((result.context ?? []).some(line => /^xcrew report .* couldn't run: ./.test(line))).toBe(true)
})

test('a failed read is said once, on the first result after it', async ($, on) => {
  let fails = true
  session(on, {
    project: args => {
      if (args.includes('--generated') && fails) throw new Error('spawn ENOENT')
      return { isGenerated: true }
    },
  })
  const first = await callTool($, 'Edit', editPbxproj)
  fails = false
  const second = await callTool($, 'mcp__xcode__BuildProject')
  expect((first.context ?? []).filter(line => line.includes("couldn't run"))).toHaveLength(1)
  expect((second.context ?? []).filter(line => line.includes("couldn't run"))).toEqual([])
})

test('a read for the band that the CLI couldn\'t answer shows there until it reads again', async ($, on) => {
  let fails = true
  const { clock } = session(on, { problems: [PIN], doctorFails: () => fails })
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  let ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /^xcrew doctor --problems .*couldn't run: ./ })).toBeDefined()
  await ui.unmount()

  fails = false
  await submitPrompt($, 'go on')
  await clock.settle()
  ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /couldn't run/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /^The project pins Xcode 26.4/ })).toBeDefined()
  await ui.unmount()
})

const BUILD = 'mcp__xcode__BuildProject'
const failedLines = (lines: readonly string[] | undefined) => (lines ?? []).filter(line => /couldn't run|no answer xcrew could read/.test(line))

test('a save of the card, which answers nothing, is no failure', async ($, on) => {
  const { clock, cli } = session(on, { problems: [], project: { isGenerated: false, root: '/work/App', branch: 'main' } })
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const first = await callTool($, BUILD)
  await clock.settle()
  const second = await callTool($, BUILD)
  await clock.settle()
  expect(cli.some(call => call.args[0] === 'card')).toBe(true)
  expect([...failedLines(first.context), ...failedLines(second.context)]).toEqual([])
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /card --save/ })).toBeUndefined()
  await ui.unmount()
})

test('the doctor outside an Apple-platform project, which answers nothing, is no failure', async ($, on) => {
  const { clock } = session(on, { notApplePlatform: true })
  await $.session.start({ cwd: '/work/notes', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /xcrew doctor/ })).toBeUndefined()
  await ui.unmount()
  expect(failedLines((await callTool($, BUILD)).context)).toEqual([])
})

test('a read that answers again before any result said its failure isn\'t said', async ($, on) => {
  let fails = true
  const { clock } = session(on, { problems: [PIN], doctorFails: () => fails })
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  fails = false
  await submitPrompt($, 'go on')
  await clock.settle()
  expect(failedLines((await callTool($, BUILD)).context)).toEqual([])
})

test('a cleared conversation starts with none of the failures of the one before', async ($, on) => {
  const { clock } = session(on, { problems: [PIN], doctorFails: () => true })
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  await $.session.end({ reason: 'clear', sessionId: 'before', resume: { id: 'before' } })
  await clock.settle()
  expect(failedLines((await callTool($, BUILD)).context)).toEqual([])
})

test('a failed read leaves the band once a warning would, and another file\'s read answering leaves it there', async ($, on) => {
  const other = '/work/App/ios/Other.xcodeproj/project.pbxproj'
  const { clock } = session(on, {
    project: args => {
      if (args.includes('--generated') && args.includes(PBXPROJ)) throw new Error('spawn ENOENT')
      return { isGenerated: true }
    },
  })
  await callTool($, 'Edit', editPbxproj)
  await callTool($, 'Edit', { ...editPbxproj, file_path: other })
  await clock.settle()
  let ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /^xcrew project --generated .*App\.xcodeproj.* couldn't run: ./ })).toBeDefined()
  await ui.unmount()
  await clock.advance(2 * 60_000 + 1)
  await clock.settle()
  ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /couldn't run/ })).toBeUndefined()
  await ui.unmount()
})

test('a background run whose report couldn\'t be read says so with its notification', async ($, on) => {
  const task = 'k4q5tm9v2'
  const handle = `MCP tool "plugin:xcrew:MobileBuildMCP/test_sim" is still running after 120s. It was moved to the background as task ${task} and keeps running; you'll receive a notification with the result when it completes.`
  const unread: Partial<Report> = { ok: true, isUnread: true, backgroundTask: task, notes: [] }
  let fails = false
  const clock = mock.clock(on)
  mock.store(on)
  on('session.surfaces', () => ({ value: ['vscode'] }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.notify', () => ({ value: { isSent: true, channel: 'terminal_bell' } }))
  on('ui.render', ($, e) => $.ui.resolve(e).Text({ children: ['as the engine draws it'] }))
  on('prompt.submit', (_, e) => ({ text: e.text, ...(e.context ? { context: e.context } : {}), origin: e.origin }))
  stubCli(on, { reports: [unread], reportFails: () => fails, project: { isGenerated: false, root: '/work/App', branch: 'main', scheme: 'App' } })
  on('tool.call', () => ({ result: {}, text: handle }))
  await callTool($, 'mcp__MobileBuildMCP__test_sim', { tool_use_id: 'toolu_bg' })
  fails = true
  const text = `<task-notification>\n<task-id>${task}</task-id>\n<status>completed</status>\n<summary>MCP task ${task} (plugin:xcrew:MobileBuildMCP/test_sim) completed.</summary>\n<result>\nthe server's result\n</result>\n</task-notification>`
  const entered = await $.prompt.submit({ text, wait: false, origin: { kind: 'task-notification' } })
  await clock.settle()
  expect((entered.context ?? []).some(line => /^xcrew report .* couldn't run: ./.test(line))).toBe(true)
})

test('/xcrew doctor that couldn\'t run says why, once', async ($, on) => {
  let fails = false
  const { clock } = session(on, { problems: [PIN], doctorFails: () => fails })
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  fails = true
  const ran = await runCommand($, 'xcrew', 'doctor')
  expect(String(ran.text)).toMatch(/^xcrew doctor --text-and-problems.* couldn't run: ./)
  expect(String(ran.text)).not.toContain('no answer')
  expect(failedLines((await callTool($, BUILD)).context)).toEqual([])
})

test('an answer the CLI gave but xcrew couldn\'t read says what came back', () => {
  expect(readLine(['project', '--hash', 'A.swift'], { stdout: 'oops', stderr: '', exitCode: 0 })).toBe("xcrew project --hash A.swift gave no answer xcrew could read: it printed something other than JSON")
  expect(readLine(['project'], { stdout: '', stderr: '', exitCode: 2 })).toBe('xcrew project gave no answer xcrew could read: it exited 2, writing nothing')
  expect(readLine(['project'], { stdout: '', stderr: '\nerror: no project here\n', exitCode: 1 })).toBe('xcrew project gave no answer xcrew could read: error: no project here')
  expect(readLine(['project'], { stdout: '', stderr: '', exitCode: 75 })).toBe("xcrew project gave no answer xcrew could read: the CLI isn't built for this version yet")
})

test('a save of the card that writes only to standard error is no failure', async ($, on) => {
  const { clock, cli } = session(on, { problems: [], project: { isGenerated: false, root: '/work/App', branch: 'main' }, cardStderr: 'xcrew: standard input was cut at 4 MB' })
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const first = await callTool($, BUILD)
  await clock.settle()
  expect(cli.some(call => call.args[0] === 'card')).toBe(true)
  expect(failedLines(first.context)).toEqual([])
})

test('a /xcrew command the CLI ended without a word says how it ended', async ($, on) => {
  session(on, { exits: args => (args[0] === 'xcode' ? 75 : undefined) })
  const ran = await runCommand($, 'xcrew', 'xcode')
  expect(String(ran.text)).toBe("xcrew xcode gave no answer xcrew could read: the CLI isn't built for this version yet")
})

test('the ledger that couldn\'t be read says which read failed, with it', async ($, on) => {
  session(on, {
    project: args => {
      if (args.includes('--branch')) throw new Error('spawn ENOENT')
      return { isGenerated: false }
    },
  })
  const result = await callTool($, 'mcp__xcrew__ledger')
  expect((result.context ?? []).some(line => line.startsWith("xcrew project --branch couldn't run: "))).toBe(true)
})

test('a read nobody waits on that keeps failing is said once, until it answers', async ($, on) => {
  const { clock } = session(on, { problems: [PIN], doctorFails: () => true })
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const first = await callTool($, BUILD)
  await submitPrompt($, 'go on')
  await clock.settle()
  const second = await callTool($, BUILD)
  expect(failedLines(first.context).filter(line => line.startsWith('xcrew doctor'))).toHaveLength(1)
  expect(failedLines(second.context)).toEqual([])
})

test('a read nobody waits on that keeps failing is said once, however far apart its failures', async ($, on) => {
  const { clock } = session(on, { problems: [PIN], doctorFails: () => true })
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const first = await callTool($, BUILD)
  await clock.advance(5 * 60_000)
  await submitPrompt($, 'go on')
  await clock.settle()
  const second = await callTool($, BUILD)
  expect(failedLines(first.context).filter(line => line.startsWith('xcrew doctor'))).toHaveLength(1)
  expect(failedLines(second.context)).toEqual([])
})

test('a background read whose times change with each run is said once, as one read', async ($, on) => {
  const { clock } = session(on, { problems: [], overlapped: () => new Error('spawn ENOENT'), project: { isGenerated: false, root: '/work/App', branch: 'main', scheme: 'App' } })
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const lines: string[] = []
  for (let run = 0; run < 3; run += 1) {
    lines.push(...failedLines((await callTool($, BUILD)).context))
    await clock.advance(60_000)
    await clock.settle()
  }
  lines.push(...failedLines((await callTool($, BUILD)).context))
  expect(lines.filter(line => line.startsWith('xcrew runs --overlapped'))).toHaveLength(1)
})

/**
 * A read is one read whatever moments or run it names: its failure, its pending line and its warning are kept under one
 * key, so an answer at other times takes them all back.
 */
test('a read is keyed without the moments and the run it names', () => {
  expect(readKey('runs --overlapped --since 1 --until 2')).toBe(readKey('runs --overlapped --since 3 --until 4'))
  expect(readKey('phase --log /a/one.log --expected 12')).toBe(readKey('phase --log /a/two.log --expected 30'))
  expect(readKey('runs --overlapped --since 1 --until 2')).toBe('runs --overlapped --since --until')
  expect(readKey('doctor --problems')).toBe('doctor --problems')
})

test('a background read that fails another way is said again', async ($, on) => {
  let status = 2
  const { clock } = session(on, { problems: [PIN], exits: args => (args[0] === 'doctor' && args.includes('--problems') ? status : undefined) })
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const first = await callTool($, BUILD)
  status = 3
  await submitPrompt($, 'go on')
  await clock.settle()
  const second = await callTool($, BUILD)
  expect(failedLines(first.context).filter(line => line.startsWith('xcrew doctor'))).toHaveLength(1)
  expect(failedLines(second.context).filter(line => line.startsWith('xcrew doctor'))).toHaveLength(1)
})

test('a read a call waits on says why each time it fails', async ($, on) => {
  session(on, {
    project: args => {
      if (args.includes('--branch')) throw new Error('spawn ENOENT')
      return { isGenerated: false }
    },
  })
  for (const result of [await callTool($, 'mcp__xcrew__ledger'), await callTool($, 'mcp__xcrew__ledger')]) {
    expect((result.context ?? []).some(line => line.startsWith("xcrew project --branch couldn't run: "))).toBe(true)
  }
})

test('a read that keeps failing stays off the band once its time there is up', async ($, on) => {
  const { clock } = session(on, {
    project: args => {
      if (args.includes('--generated')) throw new Error('spawn ENOENT')
      return { isGenerated: true }
    },
  })
  // Failing every minute, it's never quiet for a warning's time, so it isn't new again.
  await callTool($, 'Edit', editPbxproj)
  await clock.advance(60_000)
  await callTool($, 'Edit', editPbxproj)
  await clock.advance(60_001)
  await callTool($, 'Edit', editPbxproj)
  await clock.settle()
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /couldn't run/ })).toBeUndefined()
  await ui.unmount()
})

test('/xcrew ledger that couldn\'t be read says which read failed', async ($, on) => {
  session(on, {
    project: args => {
      if (args.includes('--branch')) throw new Error('spawn ENOENT')
      return { isGenerated: false }
    },
  })
  const ran = await runCommand($, 'xcrew', 'ledger')
  expect(String(ran.text)).toMatch(/\nxcrew project --branch couldn't run: ./)
})

test('each of xcrew\'s own tools says the reads that failed', () => {
  for (const tool of [AFFECTED_TOOL_NAME, EVIDENCE_TOOL_NAME, LEDGER_TOOL_NAME, LOOK_TOOL_NAME]) expect(SAYS_FAILED_READS.test(tool)).toBe(true)
})
