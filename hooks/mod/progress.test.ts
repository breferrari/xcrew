import { expect, test } from 'claude-code/testing'
import { phaseOf } from './progress'

/** Lines from xcodebuild's output as MobileBuildMCP logs it, with paths replaced. */
const PREAMBLE = `Command line invocation:
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -workspace /Users/dev/App/App.xcworkspace -scheme Utility

Target 'Utility' in project 'Foundation' (no dependencies)
`
const COMPILING = `SwiftCompile normal arm64 /Users/dev/App/Sources/Utility/CurrencyFormatter.swift (in target 'Utility' from project 'Foundation')
    cd /Users/dev/App
`
const LINKING = `Ld /Users/dev/App/Build/Products/Debug-iphonesimulator/Utility.framework/Utility normal (in target 'Utility' from project 'Foundation')
`
const SIGNING = `CodeSign /Users/dev/App/Build/Products/Debug/MockMacros (in target 'MockMacros' from project 'Mocks')
`
const OTHER_TASK = `ProcessInfoPlistFile /Users/dev/App/Build/Products/Debug-iphonesimulator/Utility.framework/Info.plist (in target 'Utility' from project 'Foundation')
`
const TESTS = `Testing started
Test case 'CurrencyFormatterTests.test_euroFormat()' passed on 'Clone 1 of iPhone 12 - xctest (26885)' (0.004 seconds)
Test case 'CurrencyFormatterTests.test_poundFormat()' failed on 'Clone 1 of iPhone 12 - xctest (26885)' (0.020 seconds)
`

test('while compiling, the phase names the module and the file', () => {
  expect(phaseOf(PREAMBLE + OTHER_TASK + COMPILING)).toBe('compiling Utility · CurrencyFormatter.swift')
})

test('linking and signing are named for their module', () => {
  expect(phaseOf(PREAMBLE + COMPILING + LINKING)).toBe('linking Utility')
  expect(phaseOf(PREAMBLE + LINKING + SIGNING)).toBe('signing MockMacros')
})

test('any other build task names the module it belongs to', () => {
  expect(phaseOf(PREAMBLE + OTHER_TASK)).toBe('building Utility')
})

test('once tests run, the phase counts them, against the last run\'s total when there is one', () => {
  expect(phaseOf(PREAMBLE + COMPILING + TESTS, 959)).toBe('testing 2 of 959')
  expect(phaseOf(PREAMBLE + COMPILING + TESTS)).toBe('testing · 2 done')
  expect(phaseOf(PREAMBLE + COMPILING + 'Testing started\n', 959)).toBe('testing 0 of 959')
})

test('more tests than last time drops the total rather than showing 1,000 of 959', () => {
  expect(phaseOf(PREAMBLE + TESTS, 1)).toBe('testing · 2 done')
})

test('a log with no task yet says nothing', () => {
  expect(phaseOf(PREAMBLE)).toBeUndefined()
  expect(phaseOf('')).toBeUndefined()
})
