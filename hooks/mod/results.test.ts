import { expect, mock, test } from 'claude-code/testing'
import * as captured from './fixtures'
import { cleanBuildText, compactTestResult, compactTestText, failuresOf, reportedDuration, summarize, testTotal } from './results'
import { callTool } from './testing'

test('MobileBuildMCP test runs: counts when they pass, the first failing test when they fail', () => {
  expect(summarize('test_sim', captured.mobileTestsPassed)).toEqual({ ok: true, detail: '3 passed' })
  expect(summarize('test_sim', captured.mobileTestsFailed)).toEqual({
    ok: false,
    detail: '1 of 3 failed · PlainTests/testConcatenation',
  })
  expect(summarize('test_sim', captured.mobileTestsBuildFailed)).toEqual({ ok: false, detail: "build failed, tests didn't run" })
})

test('MobileBuildMCP builds: the first error with its file and line', () => {
  expect(summarize('build_sim', captured.mobileBuildPassed)).toEqual({ ok: true })
  expect(summarize('build_sim', captured.mobileBuildFailed)).toEqual({
    ok: false,
    detail: "MacroProbe.swift:13 cannot convert value of type 'String' to specified type 'Int'",
  })
})

test('Xcode MCP builds: a failed build is a failure even though the server reports it as a normal result', () => {
  expect(summarize('BuildProject', captured.xcodeBuildPassed)).toEqual({ ok: true })
  expect(summarize('BuildProject', captured.xcodeBuildFailed)).toEqual({
    ok: false,
    detail: "MacroProbe.swift:13 Cannot convert value of type 'String' to specified type 'Int'",
  })
})

test('Xcode MCP test runs: failed tests are a failure though not reported as one', () => {
  expect(summarize('RunAllTests', captured.xcodeTestsPassed)).toEqual({ ok: true, detail: '5 passed' })
  expect(summarize('RunAllTests', captured.xcodeTestsFailed)).toEqual({
    ok: false,
    detail: '3 of 5 failed · MacroProbeTests/testMacro()',
  })
  expect(summarize('RunSomeTests', captured.xcodeTestsBuildFailed)).toEqual({ ok: false, detail: "build failed, tests didn't run" })
})

test('several build errors are counted', () => {
  const errors = [1, 2, 3].map(n => ({ classification: 'error', filePath: `/a/View${n}.swift`, lineNumber: n, message: `problem ${n}` }))
  expect(summarize('BuildProject', { isError: false, text: JSON.stringify({ buildResult: 'The build failed', errors }) })).toEqual({
    ok: false,
    detail: '3 errors · View1.swift:1 problem 1',
  })
})

test('output in a shape nobody captured falls back to whether the server reported an error', () => {
  expect(summarize('test_sim', { isError: true, text: 'something new' })).toEqual({ ok: false })
  expect(summarize('build_sim', { isError: false, text: 'also new' })).toEqual({ ok: true })
  expect(summarize('BuildProject', { isError: false, text: '{"unexpected":true}' })).toEqual({ ok: true })
})

test('a long detail is shortened so the toast stays one line', () => {
  const message = 'x'.repeat(200)
  const result = summarize('BuildProject', {
    isError: false,
    text: JSON.stringify({ buildResult: 'The build failed', errors: [{ classification: 'error', filePath: '/a/B.swift', lineNumber: 1, message }] }),
  })
  expect(result.detail?.length).toBe(100)
  expect(result.detail?.endsWith('…')).toBe(true)
})

test('the toast carries the outcome and its detail', async ($, on) => {
  mock.clock(on)
  mock.store(on)
  const toasts: string[] = []
  on('ui.toast', (_, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  on('ui.status', () => ({ value: undefined }))
  const answers = [captured.xcodeBuildFailed, captured.mobileTestsFailed, captured.xcodeTestsPassed]
  on('tool.call', () => {
    const next = answers.shift()!
    return next.isError ? { result: {}, isError: true, text: next.text } : { result: {}, text: next.text }
  })

  await callTool($, 'mcp__xcode__BuildProject')
  await callTool($, 'mcp__plugin_xcrew_MobileBuildMCP__test_sim')
  await callTool($, 'mcp__xcode__RunAllTests')

  expect(toasts).toEqual([
    "✗ BuildProject · 0:01 · MacroProbe.swift:13 Cannot convert value of type 'String' to specified type 'Int'",
    '✗ test_sim · 0:12 · 1 of 3 failed · PlainTests/testConcatenation',
    '✓ RunAllTests · 0:00 · 5 passed',
  ])
})

test('each server reports how long the run itself took, which leaves out hooks and permission prompts', () => {
  expect(reportedDuration(captured.mobileTestsPassed.text)).toBe(14_544)
  expect(reportedDuration(captured.mobileTestsFailed.text)).toBe(12_300)
  expect(reportedDuration(captured.mobileBuildFailed.text)).toBe(3_200)
  expect(reportedDuration(captured.xcodeBuildPassed.text)).toBe(3_857)
  expect(reportedDuration(captured.xcodeTestsPassed.text)).toBeUndefined()
  expect(reportedDuration('Build succeeded')).toBeUndefined()
})

test('a test run says how many tests it ran, so the next run can show its progress against that', () => {
  expect(testTotal(captured.mobileTestsPassed.text)).toBe(3)
  expect(testTotal(captured.mobileTestsFailed.text)).toBe(3)
  expect(testTotal(captured.xcodeTestsPassed.text)).toBe(5)
  expect(testTotal(captured.mobileBuildPassed.text)).toBeUndefined()
})

test('MobileBuildMCP\'s failing tests are listed once each, with the message and where it failed', () => {
  expect(failuresOf(captured.mobileTestsFailed.text)).toEqual([
    {
      title: 'PlainTests/testConcatenation',
      message: 'XCTAssertEqual failed: ("ab") is not equal to ("ba") - strings join left to right',
      where: 'PlainTests.swift:5',
    },
  ])
})

test('compile errors are listed by file and line, from either server', () => {
  expect(failuresOf(captured.mobileBuildFailed.text)).toEqual([
    { title: 'MacroProbe.swift:13', message: "cannot convert value of type 'String' to specified type 'Int'" },
  ])
  expect(failuresOf(captured.xcodeBuildFailed.text)).toEqual([
    { title: 'MacroProbe.swift:13', message: "Cannot convert value of type 'String' to specified type 'Int'" },
  ])
})

test('a test run whose build failed lists why it never ran', () => {
  const failures = failuresOf(captured.mobileTestsBuildFailed.text)
  expect(failures.map(failure => failure.title)).toEqual(['LLVM Profile Error', 'Failed to build workspace MacroProbe with scheme MacroProbe-Package.'])
  expect(failures[1]?.message).toMatch(/^Cannot test target “MacroProbeTests” on “iPhone 16”: Missing test product/)
})

test('the Xcode MCP\'s failing tests carry their own message and location', () => {
  expect(failuresOf(captured.xcodeTestsFailed.text)).toEqual([
    { title: 'MacroProbeTests/testMacro()', message: 'Issue recorded: Macro expansion did not produce the expected expanded source', where: 'MacroProbeTests.swift:19' },
    {
      title: 'MacroProbeTests/testMacroWithStringLiteral()',
      message: 'Issue recorded: Macro expansion did not produce the expected expanded source',
      where: 'MacroProbeTests.swift:35',
    },
    { title: 'PlainTests/testConcatenation()', message: 'XCTAssertEqual failed: ("ab") is not equal to ("ba") - strings join left to right', where: 'PlainTests.swift:5' },
  ])
})

test('a passing run has no failures', () => {
  for (const output of [captured.mobileTestsPassed, captured.mobileBuildPassed, captured.xcodeBuildPassed, captured.xcodeTestsPassed]) {
    expect(failuresOf(output.text)).toEqual([])
  }
})

test('an XCTFail reads as its own message, without XCTest\'s "failed - " in front', () => {
  const text = `🧪 Test

Test Failures (1):

  ✗ FormatterTests / test_symbol(): failed - deliberate failure

❌ 1 test failed, 0 passed, 0 skipped (⏱️ 30.7s)`
  expect(failuresOf(text)).toEqual([{ title: 'FormatterTests/test_symbol', message: 'deliberate failure' }])
})

/** A failing run's text as MobileBuildMCP returns it with `showTestTiming` on: every passing test listed. */
function failingRunText(passing: number): string {
  const passed = Array.from({ length: passing }, (_, index) => `  ✅ FormatterTests/test_case${index}() (0.001s)`)
  return [
    '🧪 Test',
    '',
    'Test Failures (1):',
    '',
    '  ✗ FormatterTests / test_symbol(): XCTAssertEqual failed: ("4") is not equal to ("3")',
    '',
    'Test Results:',
    ...passed,
    '  ❌ FormatterTests/test_symbol() (0.010s)',
    '',
    `❌ 1 test failed, ${passing} passed, 0 skipped (⏱️ 65.0s)`,
    '  └ Files:',
    '     └── ~/Library/Developer/MobileBuildMCP/workspaces/sample-0000/logs/test_sim.log — Build Logs',
  ].join('\n')
}

test('a failing run\'s text keeps its failures and summary, and counts its passing tests instead of listing them', () => {
  expect(compactTestText(failingRunText(40))).toBe(
    [
      '🧪 Test',
      '',
      'Test Failures (1):',
      '',
      '  ✗ FormatterTests / test_symbol(): XCTAssertEqual failed: ("4") is not equal to ("3")',
      '',
      'Test Results:',
      '  (40 passing tests left out; failing tests are listed in full above)',
      '',
      '❌ 1 test failed, 40 passed, 0 skipped (⏱️ 65.0s)',
      '  └ Files:',
      '     └── ~/Library/Developer/MobileBuildMCP/workspaces/sample-0000/logs/test_sim.log — Build Logs',
    ].join('\n'),
  )
})

test('a short list of passing tests is left as the server wrote it', () => {
  expect(compactTestText(failingRunText(5))).toBeUndefined()
  expect(compactTestText(captured.mobileBuildFailed.text)).toBeUndefined()
})

test('a test run that ran no tests is not a success, whatever the server says', () => {
  expect(summarize('test_sim', captured.mobileTestsNoneRan)).toEqual({ ok: false, detail: 'no tests ran' })
})

test('a list Claude Code already cut in the middle is counted whole, its marker and fragments dropped', () => {
  const cut = failingRunText(40).replace('  ✅ FormatterTests/test_case20() (0.001s)', '\n... [71437 characters truncated] ...\n\nTests/test_case20() (0.001s)')
  const compact = compactTestText(cut) ?? ''
  expect(compact).toContain('Test Results:\n  (40 passing tests left out; failing tests are listed in full above)\n\n❌ 1 test failed, 40 passed')
  expect(compact).not.toContain('truncated')
  expect(compact).not.toContain('test_case20')
})

test('skipped tests keep their lines: only passing ones are counted', () => {
  const withSkip = failingRunText(40).replace('  ❌ FormatterTests/test_symbol() (0.010s)', '  ⏭️ FormatterTests/test_skipped() (0.000s)\n  ❌ FormatterTests/test_symbol() (0.010s)')
  expect(compactTestText(withSkip)).toContain('  (40 passing tests left out; failing tests are listed in full above)\n  ⏭️ FormatterTests/test_skipped() (0.000s)\n\n❌')
})

test('a compile error is counted once: the compiler\'s caret line is part of it, not a second error', () => {
  const cleaned = cleanBuildText(captured.mobileBuildFailed.text) ?? ''
  expect(cleaned).toContain('Errors (1):')
  expect(cleaned).not.toContain('✗ |')
  expect(cleaned).toContain("✗ cannot convert value of type 'String' to specified type 'Int'\n    /Users/dev/MacroProbe/Sources/MacroProbe/MacroProbe.swift:13")
  expect(cleanBuildText(captured.mobileTestsFailed.text)).toBeUndefined()
})

test('the note for a left-out list gives no count of its own, so it can\'t disagree with the summary\'s', () => {
  const compact = JSON.parse(compactTestResult(captured.mobileTestsPassed.text, '/saved.txt') ?? '{}')
  expect(compact.data.testCases).toBe('per-test list left out to keep this result short; the counts above are complete, and the full result is in /saved.txt')
})

test('a skipped test keeps the reason added under it when the list is compacted', () => {
  const annotated = failingRunText(40).replace('  ❌ FormatterTests/test_symbol() (0.010s)', '  ⏭️ FormatterTests/test_skipped() (0.000s)\n      skipped: waiting on the new API')
  expect(compactTestText(annotated)).toContain('  ⏭️ FormatterTests/test_skipped() (0.000s)\n      skipped: waiting on the new API\n')
})
