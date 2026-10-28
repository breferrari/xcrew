/**
 * What a build, test or run call came to, read from the server's own output. Each reader matches
 * one shape captured from a real server (see `fixtures.ts`); output in any other shape falls back
 * to whether the server reported a tool error, so a server update degrades the toast, not breaks it.
 */
export type ToolOutput = { isError: boolean; text: string }
export type Summary = { ok: boolean; detail?: string }

/** Keeps the toast to one line. */
const MAX_DETAIL = 100
const TESTS_DID_NOT_RUN = "build failed, tests didn't run"
/** A test run whose counts are all 0 reports SUCCEEDED; it's usually a filter that matched nothing. */
const NO_TESTS_RAN = 'no tests ran'

export function summarize(_tool: string, output: ToolOutput): Summary {
  const json = parseObject(output.text)
  const summary = (json && (fromMobileBuildMCP(json) ?? fromXcodeMCP(json))) ?? fromMobileBuildMCPText(output.text) ?? { ok: !output.isError }
  return summary.detail ? { ...summary, detail: shorten(summary.detail) } : summary
}

type Json = Record<string, unknown>

function parseObject(text: string): Json | undefined {
  try {
    const value: unknown = JSON.parse(text)
    return value !== null && typeof value === 'object' ? (value as Json) : undefined
  } catch {
    return undefined
  }
}

/** MobileBuildMCP's JSON, which it returns when a build or test run succeeds. */
function fromMobileBuildMCP(json: Json): Summary | undefined {
  if (typeof json.schema !== 'string' || !json.schema.startsWith('mobilebuildmcp.output.')) return undefined
  const summary = (json.data as Json | undefined)?.summary as Json | undefined
  if (!summary) return undefined
  const ok = summary.status === 'SUCCEEDED'
  const counts = summary.counts as { passed?: number; failed?: number; skipped?: number } | undefined
  if (!counts) return { ok }
  const failed = counts.failed ?? 0
  const total = (counts.passed ?? 0) + failed + (counts.skipped ?? 0)
  if (total === 0) return { ok: false, detail: NO_TESTS_RAN }
  return failed > 0 ? { ok: false, detail: `${failed} of ${total} failed` } : { ok, detail: `${counts.passed ?? 0} passed` }
}

/** The Xcode MCP's JSON: it reports failed builds and failed tests as normal results. */
function fromXcodeMCP(json: Json): Summary | undefined {
  if (json.type === 'error') {
    const message = String(json.data ?? '')
    return { ok: false, detail: /build action failed/i.test(message) ? TESTS_DID_NOT_RUN : message || undefined }
  }
  const counts = json.counts as { passed?: number; failed?: number; total?: number } | undefined
  if (counts) {
    const failed = counts.failed ?? 0
    if ((counts.total ?? (counts.passed ?? 0) + failed) === 0) return { ok: false, detail: NO_TESTS_RAN }
    if (failed === 0) return { ok: true, detail: `${counts.passed ?? 0} passed` }
    const results = (json.results as { identifier?: string; state?: string }[] | undefined) ?? []
    const first = results.find(result => result.state === 'Failed')?.identifier
    return { ok: false, detail: `${failed} of ${counts.total ?? failed} failed${first ? ` · ${first}` : ''}` }
  }
  if (typeof json.buildResult === 'string' && Array.isArray(json.errors)) {
    const errors = (json.errors as { classification?: string; filePath?: string; lineNumber?: number; message?: string }[])
      .filter(error => error.classification !== 'warning')
    const [first] = errors
    if (!first) return { ok: true }
    const where = first.filePath ? `${basename(first.filePath)}:${first.lineNumber ?? '?'} ` : ''
    return { ok: false, detail: `${errors.length > 1 ? `${errors.length} errors · ` : ''}${where}${first.message ?? ''}`.trim() }
  }
  return undefined
}

/** MobileBuildMCP's text, which it returns instead of JSON when a build or test run fails. */
function fromMobileBuildMCPText(text: string): Summary | undefined {
  const tests = /❌ (\d+) tests? failed, (\d+) passed, (\d+) skipped/.exec(text)
  if (tests) {
    const [failed = 0, passed = 0, skipped = 0] = tests.slice(1).map(Number)
    const first = /^\s*✗ (.+?) \/ (\S+?)(?:\(\))?: /m.exec(text)
    return { ok: false, detail: `${failed} of ${failed + passed + skipped} failed${first ? ` · ${first[1]}/${first[2]}` : ''}` }
  }
  if (text.startsWith('🧪') && text.includes('❌ Test failed')) return { ok: false, detail: TESTS_DID_NOT_RUN }
  if (text.includes('❌ Build failed')) {
    const first = /^\s*✗ (.+)\n\s*(\/\S+):(\d+)/m.exec(text)
    const [, message, path, line] = first ?? []
    return { ok: false, detail: message && path ? `${basename(path)}:${line} ${message}` : undefined }
  }
  return undefined
}

function basename(path: string): string {
  return path.slice(path.lastIndexOf('/') + 1)
}

function shorten(text: string): string {
  return text.length > MAX_DETAIL ? `${text.slice(0, MAX_DETAIL - 1)}…` : text
}

/**
 * How long the server says the run took, in milliseconds, which leaves out the hooks and
 * permission prompts around the call: MobileBuildMCP's `durationMs` or its `(⏱️ 12.3s)`, the
 * Xcode MCP's `elapsedTime`. The Xcode MCP's test runs report none.
 */
export function reportedDuration(text: string): number | undefined {
  const json = parseObject(text)
  if (json) {
    const summary = (json.data as Json | undefined)?.summary as Json | undefined
    if (typeof summary?.durationMs === 'number') return summary.durationMs
    if (typeof json.elapsedTime === 'number') return Math.round(json.elapsedTime * 1000)
    return undefined
  }
  const seconds = /\(⏱️ ([\d.]+)s\)/.exec(text)?.[1]
  return seconds === undefined ? undefined : Math.round(Number(seconds) * 1000)
}

/** How many tests a test run ran, from either server's counts. */
export function testTotal(text: string): number | undefined {
  const json = parseObject(text)
  const counts = ((json?.data as Json | undefined)?.summary as Json | undefined)?.counts ?? json?.counts
  if (counts && typeof counts === 'object') {
    const { passed = 0, failed = 0, skipped = 0, total } = counts as { passed?: number; failed?: number; skipped?: number; total?: number }
    return total ?? passed + failed + skipped
  }
  const tests = /❌ (\d+) tests? failed, (\d+) passed, (\d+) skipped/.exec(text)
  return tests ? tests.slice(1).reduce((sum, count) => sum + Number(count), 0) : undefined
}

/** One failing test or compile error, for the failure pane. */
export type Failure = { title: string; message: string; where?: string }

/** Every failure a run reported, from each shape `summarize` reads; none for a passing run. */
export function failuresOf(text: string): Failure[] {
  const json = parseObject(text)
  if (json) return failuresFromXcodeMCP(json)
  return failuresFromMobileBuildMCPText(text)
}

function failuresFromXcodeMCP(json: Json): Failure[] {
  if (Array.isArray(json.errors)) {
    return (json.errors as { classification?: string; filePath?: string; lineNumber?: number; message?: string }[])
      .filter(error => error.classification !== 'warning')
      .map(error => ({ title: error.filePath ? `${basename(error.filePath)}:${error.lineNumber ?? '?'}` : 'error', message: error.message ?? '' }))
  }
  if (Array.isArray(json.results)) {
    return (json.results as { identifier?: string; state?: string; errorMessages?: string[] }[])
      .filter(result => result.state === 'Failed')
      .map(result => {
        // `Tests/PlainTests.swift:5 PlainTests/testConcatenation(): XCTAssertEqual failed: …`
        const raw = result.errorMessages?.[0] ?? ''
        const located = /^(\S+?):(\d+) \S+?: (.*)$/s.exec(raw)
        return located
          ? { title: result.identifier ?? 'test', message: located[3] ?? '', where: `${basename(located[1] ?? '')}:${located[2]}` }
          : { title: result.identifier ?? 'test', message: raw }
      })
  }
  return []
}

/** MobileBuildMCP's text: `✗ Suite / test: message` or `✗ message`, each maybe followed by its `/path:line`. */
function failuresFromMobileBuildMCPText(text: string): Failure[] {
  const failures: Failure[] = []
  const seen = new Set<string>()
  const lines = text.split('\n')
  lines.forEach((line, index) => {
    const entry = /^\s*✗ (.+)$/.exec(line)?.[1]
    // Its second copy of a compiler error is the source excerpt, drawn with `|`.
    if (!entry || entry.startsWith('|')) return
    const path = /^\s+(\/\S+):(\d+)\s*$/.exec(lines[index + 1] ?? '')
    const where = path ? `${basename(path[1] ?? '')}:${path[2]}` : undefined
    const test = /^(.+?) \/ (\S+?)(?:\(\))?: (.*)$/.exec(entry)
    if (test) {
      const title = `${test[1]}/${test[2]}`
      // It lists a failing test twice, once with its location; the first is kept.
      if (seen.has(title)) return
      seen.add(title)
      // XCTest words an XCTFail as `failed - <message>`; the message is what was written.
      failures.push({ title, message: (test[3] ?? '').replace(/^failed - /, ''), ...(where ? { where } : {}) })
      return
    }
    if (where) {
      failures.push({ title: where, message: entry })
      return
    }
    const split = entry.indexOf(': ')
    failures.push(split > 0 ? { title: entry.slice(0, split), message: entry.slice(split + 2) } : { title: entry, message: '' })
  })
  return failures
}

/**
 * A MobileBuildMCP test result without its per-test list, which is nearly all of a large run's
 * result (127 of 130 KB for 959 tests): the summary, counts, failures and artifacts stay, and the
 * list is pointed to in `savedPath`. Undefined for anything else.
 */
export function compactTestResult(text: string, savedPath: string): string | undefined {
  const json = parseObject(text)
  const data = json?.data as Json | undefined
  if (json?.schema !== 'mobilebuildmcp.output.test-result' || !Array.isArray(data?.testCases)) return undefined
  // The list's own size, which can be one short of the summary's counts: those come from the result bundle.
  const note = `per-test list (${data.testCases.length} entries) left out to keep this result short; the full result is in ${savedPath}`
  return JSON.stringify({ ...json, data: { ...data, testCases: note } })
}

/** Passing tests listed past this many are counted instead: a failing run's list is what pushes it over the limit. */
const PASSING_LIST_LIMIT = 20

/**
 * MobileBuildMCP's text for a failing test run, with `showTestTiming` on, lists every passing test
 * under `Test Results:`. This keeps the failures, the failing tests' lines and the summary, and
 * counts the passing ones. Undefined when the list is short or the text is another shape.
 */
export function compactTestText(text: string): string | undefined {
  if (!text.startsWith('🧪 Test')) return undefined
  const lines = text.split('\n')
  const start = lines.indexOf('Test Results:')
  if (start === -1) return undefined
  // The list runs to the summary line; a blank line inside it is where Claude Code cut a long one.
  const summary = lines.findIndex((line, index) => index > start && /^(❌|✅) \d+ tests? /.test(line))
  let end = summary === -1 ? start + 1 : summary
  if (summary === -1) while (end < lines.length && (lines[end] ?? '').trim() !== '') end += 1
  while (end > start + 1 && (lines[end - 1] ?? '').trim() === '') end -= 1
  const section = lines.slice(start + 1, end)
  const listed = section.filter(line => line.trimStart().startsWith('✅')).length
  if (listed <= PASSING_LIST_LIMIT) return undefined
  // The summary's count, since Claude Code may already have cut the middle of a long list.
  const passed = Number(/❌ \d+ tests? failed, (\d+) passed/.exec(text)?.[1] ?? listed)
  const failing = section.filter(line => line.includes('❌'))
  return [...lines.slice(0, start + 1), `  (${passed} passing tests left out)`, ...failing, ...lines.slice(end)].join('\n')
}
