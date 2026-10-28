import { expect, mock, test } from 'claude-code/testing'
import * as captured from './fixtures'
import { summarize } from './results'
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
    "✗ BuildProject · 0:00 · MacroProbe.swift:13 Cannot convert value of type 'String' to specified type 'Int'",
    '✗ test_sim · 0:00 · 1 of 3 failed · PlainTests/testConcatenation',
    '✓ RunAllTests · 0:00 · 5 passed',
  ])
})
