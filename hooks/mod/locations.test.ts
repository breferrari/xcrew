import { expect, mock, test } from 'claude-code/testing'
import * as captured from './fixtures'
import { crashSummaryOf, expectedFailuresNoteOf, resultBundleOf, skipReasonOf, sourceLocationOf, withLocations } from './locations'
import { callTool, runCommand } from './testing'

test('a failing test\'s details give the file and line it failed at; a crash\'s give none', () => {
  expect(sourceLocationOf(captured.xcresultFailureDetails)).toBe('/Users/dev/App/Tests/FormatterTests.swift:7')
  expect(sourceLocationOf(captured.xcresultCrashDetails)).toBeUndefined()
  expect(sourceLocationOf('not json')).toBeUndefined()
})

test('the result bundle is found from the paths the result lists', () => {
  expect(resultBundleOf(captured.mobileTestsFailedUnlocated.text, '/Users/dev')).toBe(
    '/Users/dev/Library/Developer/MobileBuildMCP/workspaces/sample-0000/result-bundles/test_sim_1.xcresult',
  )
  expect(resultBundleOf(captured.mobileBuildFailed.text, '/Users/dev')).toBeUndefined()
})

test('each failure gets its location on the next line, as MobileBuildMCP writes it for compile errors', () => {
  const located = withLocations(captured.mobileTestsFailedUnlocated.text, new Map([['FormatterTests/test_symbol', '/Users/dev/App/Tests/FormatterTests.swift:7']]))
  expect(located).toContain('  ✗ FormatterTests / test_symbol(): failed - deliberate failure\n    /Users/dev/App/Tests/FormatterTests.swift:7\n')
})

test('a failing run reaches Claude and the pane with where each test failed, read from the result bundle', async ($, on) => {
  mock.clock(on)
  mock.store(on)
  mock.env(on, { HOME: '/Users/dev' })
  const runs: (readonly string[])[] = []
  on('session.surfaces', () => ({ value: [] }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('process.run', (_, e) => {
    runs.push(e.argv)
    const stdout = e.argv.includes('test-details') ? captured.xcresultFailureDetails : ''
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('tool.call', () => ({ result: {}, text: captured.mobileTestsFailedUnlocated.text, isError: true }))

  const ran = await callTool($, 'mcp__MobileBuildMCP__test_sim')

  expect(runs).toContainEqual([
    'xcrun', 'xcresulttool', 'get', 'test-results', 'test-details', '--test-id', 'FormatterTests/test_symbol()',
    '--path', '/Users/dev/Library/Developer/MobileBuildMCP/workspaces/sample-0000/result-bundles/test_sim_1.xcresult', '--compact',
  ])
  expect(ran.result).toContain('failed - deliberate failure\n    /Users/dev/App/Tests/FormatterTests.swift:7')
  expect((await runCommand($, 'xcrew', 'failures')).text).toBe('1 failure from test_sim, in the pane.')
})

test('a failure MobileBuildMCP already located is not looked up again', async ($, on) => {
  mock.clock(on)
  mock.store(on)
  mock.env(on, { HOME: '/Users/dev' })
  const runs: (readonly string[])[] = []
  on('session.surfaces', () => ({ value: [] }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('process.run', (_, e) => {
    runs.push(e.argv)
    return { value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('tool.call', () => ({ result: {}, text: captured.mobileTestsFailed.text, isError: true }))

  await callTool($, 'mcp__MobileBuildMCP__test_sim')

  expect(runs.filter(argv => argv.includes('test-details'))).toEqual([])
})

test('a crash log gives the exception and the top frames of the thread that crashed', () => {
  expect(crashSummaryOf(captured.crashLog)).toEqual([
    'crashed: EXC_BREAKPOINT (SIGTRAP)',
    'libswiftCore.dylib  closure #1 in closure #1 in _assertionFailure(_:_:file:line:flags:)',
    'libswiftCore.dylib  _assertionFailure(_:_:file:line:flags:)',
    'AppTests  implicit closure #1 in FormatterTests.test_crash()',
    'AppTests  partial apply for implicit closure #1 in FormatterTests.test_crash()',
    'libXCTestSwiftSupport.dylib  closure #1 in XCTAssertEqual<A>(_:_:_:file:line:)',
  ])
  expect(crashSummaryOf('not a crash log')).toBeUndefined()
})

test('a skipped test\'s details give the reason it was skipped', () => {
  expect(skipReasonOf(captured.xcresultSkipDetails)).toBe('waiting on the new API')
  expect(skipReasonOf(captured.xcresultFailureDetails)).toBeUndefined()
})

test('a crash reaches Claude with its exception and frames, and a skip with its reason', async ($, on) => {
  mock.clock(on)
  mock.store(on)
  mock.env(on, { HOME: '/Users/dev' })
  const runs: (readonly string[])[] = []
  on('session.surfaces', () => ({ value: [] }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('process.run', (_, e) => {
    runs.push(e.argv)
    const id = e.argv[e.argv.indexOf('--test-id') + 1]
    const stdout =
      e.argv[0] === 'mktemp' ? '/tmp/xcrew-crash\n'
      : e.argv.includes('test-details') && id === 'FormatterTests/test_skipped()' ? captured.xcresultSkipDetails
      : e.argv.includes('test-details') ? captured.xcresultCrashDetails
      : ''
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('fs.list', () => ({ value: [{ name: 'crash.ips', kind: 'file', size: 1, mtimeMs: 0, isLink: false }, { name: 'manifest.json', kind: 'file', size: 1, mtimeMs: 0, isLink: false }] }))
  on('fs.read', () => ({ value: captured.crashLog }))
  on('tool.call', () => ({ result: {}, text: captured.mobileTestsCrashedAndSkipped.text, isError: true }))

  const ran = await callTool($, 'mcp__MobileBuildMCP__test_sim')

  const shown = ran.result as string
  expect(shown).toContain('Crash: xctest at implicit closure #1 in FormatterTests.test_crash()\n      crashed: EXC_BREAKPOINT (SIGTRAP)\n      libswiftCore.dylib  closure #1 in closure #1 in _assertionFailure')
  expect(shown).toContain('  ⏭️ FormatterTests/test_skipped() (0.000s)\n      skipped: waiting on the new API')
  expect(runs).toContainEqual(['rm', '-rf', '/tmp/xcrew-crash'])
})

test('a run\'s expected failures are named with the true total, since the counts leave them out', () => {
  expect(expectedFailuresNoteOf(captured.xcresultSummaryWithExpectedFailures)).toBe(
    'xcrew: 2 tests also ran as expected failures (XCTExpectFailure). They count as neither passed nor failed in the result: 961 tests ran in all.',
  )
  expect(expectedFailuresNoteOf('{"totalTestCount":3,"passedTests":3,"expectedFailures":0}')).toBeUndefined()
  expect(expectedFailuresNoteOf('not json')).toBeUndefined()
})

test('the result bundle is found in a passing run\'s JSON too', () => {
  expect(resultBundleOf(captured.mobileTestsPassed.text, '/Users/dev')).toBe('/Users/dev/Library/Developer/MobileBuildMCP/workspaces/sample-0000/result-bundles/test_sim.xcresult')
})

test('Claude is told about a run\'s expected failures', async ($, on) => {
  mock.clock(on)
  mock.store(on)
  mock.env(on, { HOME: '/Users/dev' })
  on('session.surfaces', () => ({ value: [] }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('process.run', (_, e) => {
    const stdout = e.argv.includes('summary') ? captured.xcresultSummaryWithExpectedFailures : ''
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('tool.call', () => ({ result: {}, text: captured.mobileTestsPassed.text }))

  const ran = await callTool($, 'mcp__MobileBuildMCP__test_sim')

  expect(ran.context).toEqual(['xcrew: 2 tests also ran as expected failures (XCTExpectFailure). They count as neither passed nor failed in the result: 961 tests ran in all.'])
})
