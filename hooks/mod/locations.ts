import type { EngineInterface } from 'claude-code'

/**
 * What the run's result bundle adds to a failing MobileBuildMCP test run: where each failure
 * happened (on parallel simulator clones xcodebuild logs none), a crash's exception and frames,
 * and why each skipped test was skipped. One `xcresulttool` call per test, each well under a second.
 */

/** At most this many tests are looked up: past it, the first ones are enough to start from. */
const MOST_LOOKUPS = 10
/** Frames of the crashed thread shown: enough to reach the test's own code from the crash. */
const TOP_FRAMES = 5

/** `✗ Suite / test(): message`, as MobileBuildMCP lists a failing test. */
const FAILURE = /^\s*✗ (.+?) \/ (\S+?): (.*)$/
/** `⏭️ Suite/test() (0.000s)`, as it lists a skipped one. */
const SKIPPED = /^\s*⏭\uFE0F? (\S+?)\/(\S+?) \(/
const PATH_LINE = /^\s+\/\S+:\d+\s*$/

/** A test as `Suite/test`: MobileBuildMCP lists one failure both with and without the `()`. */
function key(suite: string, test: string): string {
  return `${suite}/${test.replace(/\(\)$/, '')}`
}

/** Every node of a JSON value, breadth first. */
function* nodes(json: unknown): Generator<Record<string, unknown>> {
  const queue: unknown[] = [json]
  while (queue.length > 0) {
    const node = queue.shift()
    if (Array.isArray(node)) queue.push(...node)
    else if (node && typeof node === 'object') {
      yield node as Record<string, unknown>
      queue.push(...Object.values(node))
    }
  }
}

function parse(text: string): unknown {
  try {
    return JSON.parse(text)
  } catch {
    return undefined
  }
}

/** The first source location in `xcresulttool get test-results test-details` output, as `path:line`. */
export function sourceLocationOf(details: string): string | undefined {
  for (const node of nodes(parse(details))) {
    const location = node.sourceLocation as { filePath?: string; lineNumber?: number } | undefined
    if (location?.filePath && location.lineNumber !== undefined) return `${location.filePath}:${location.lineNumber}`
  }
  return undefined
}

type Skip = { reason?: string; seconds: number }

/**
 * Each skipped test in `xcresulttool get test-results tests` output, keyed `Suite/test`, with why it
 * was skipped (its `Test skipped - <reason>` message) and how long it ran.
 */
export function skippedTestsOf(listing: string): Map<string, Skip> {
  const skips = new Map<string, Skip>()
  for (const node of nodes(parse(listing))) {
    if (node.nodeType !== 'Test Case' || node.result !== 'Skipped' || typeof node.nodeIdentifier !== 'string') continue
    const message = (node.children as { nodeType?: string; name?: string }[] | undefined)?.find(child => child.nodeType === 'Skip Message')?.name
    const [suite, test] = node.nodeIdentifier.split('/')
    skips.set(key(suite ?? '', test ?? ''), {
      reason: message?.startsWith('Test skipped - ') ? message.slice('Test skipped - '.length) : message,
      seconds: typeof node.durationInSeconds === 'number' ? node.durationInSeconds : 0,
    })
  }
  return skips
}

/** A crash log's exception and the top frames of the thread that crashed, as `image  symbol`. */
export function crashSummaryOf(log: string): string[] | undefined {
  const report = parse(log.slice(log.indexOf('\n') + 1)) as
    | { faultingThread?: number; exception?: { type?: string; signal?: string }; usedImages?: { name?: string }[]; threads?: { frames?: { imageIndex?: number; symbol?: string }[] }[] }
    | undefined
  const frames = report?.threads?.[report.faultingThread ?? -1]?.frames
  if (!report || !frames) return undefined
  const exception = report.exception?.type ? [`crashed: ${report.exception.type}${report.exception.signal ? ` (${report.exception.signal})` : ''}`] : []
  const top = frames.slice(0, TOP_FRAMES).map(frame => `${report.usedImages?.[frame.imageIndex ?? -1]?.name ?? '?'}  ${frame.symbol ?? '?'}`)
  return [...exception, ...top]
}

/** The run's `.xcresult`: from a passing run's JSON, or the workspace folder and bundle path a failing run's text lists. */
export function resultBundleOf(text: string, home: string): string | undefined {
  const fromJson = ((parse(text) as { data?: { artifacts?: { xcresultPath?: unknown } } } | undefined)?.data?.artifacts?.xcresultPath)
  if (typeof fromJson === 'string') return fromJson.replace(/^~/, home)
  const folder = /└── (~?\/\S+\/)\s*$/m.exec(text)?.[1]
  const bundle = /(result-bundles\/\S+\.xcresult) — Result Bundle/.exec(text)?.[1]
  if (!folder || !bundle) return undefined
  return `${folder.replace(/^~/, home)}${bundle}`
}

/**
 * Lines to add under each failure (keyed `Suite/test`) and under each skipped test, and the lines of
 * skipped tests the text leaves out, which go at the end of its Test Results list.
 */
type Notes = { failures: ReadonlyMap<string, readonly string[]>; skipped: ReadonlyMap<string, readonly string[]>; unlisted?: readonly string[] }

/** `❌ 2 tests failed, 959 passed, 1 skipped (⏱️ 47.4s)`, the run's summary line. */
const SUMMARY = /^(❌|✅) \d+ tests? /

/** Writes the notes: a failure's go after it and its location line, a skipped test's after its line. */
function annotate(text: string, notes: Notes): string {
  const lines = text.split('\n')
  const out: string[] = []
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index] ?? ''
    if (SUMMARY.test(line) && notes.unlisted?.length) {
      const blank = (out.at(-1) ?? '').trim() === '' ? out.pop() : undefined
      out.push(...notes.unlisted)
      if (blank !== undefined) out.push(blank)
    }
    out.push(line)
    const failure = FAILURE.exec(line)
    if (failure) {
      if (PATH_LINE.test(lines[index + 1] ?? '')) out.push(lines[++index] ?? '')
      out.push(...(notes.failures.get(key(failure[1] ?? '', failure[2] ?? '')) ?? []))
      continue
    }
    const skipped = SKIPPED.exec(line)
    if (skipped) out.push(...(notes.skipped.get(key(skipped[1] ?? '', skipped[2] ?? '')) ?? []))
  }
  return out.join('\n')
}

/** Each found location on the line after its failure, as MobileBuildMCP writes compile errors. */
export function withLocations(text: string, locations: ReadonlyMap<string, string>): string {
  return annotate(text, { failures: new Map([...locations].map(([test, location]) => [test, [`    ${location}`]])), skipped: new Map() })
}

type Failure = { test: string; isLocated: boolean; isCrash: boolean }

function failuresIn(text: string): Failure[] {
  const lines = text.split('\n')
  const found = new Map<string, Failure>()
  lines.forEach((line, index) => {
    const failure = FAILURE.exec(line)
    if (!failure) return
    const test = key(failure[1] ?? '', failure[2] ?? '')
    const seen = found.get(test) ?? { test, isLocated: false, isCrash: false }
    found.set(test, {
      test,
      isLocated: seen.isLocated || PATH_LINE.test(lines[index + 1] ?? ''),
      isCrash: seen.isCrash || (failure[3] ?? '').startsWith('Crash:'),
    })
  })
  return [...found.values()]
}

function skippedIn(text: string): string[] {
  return text.split('\n').flatMap(line => {
    const skipped = SKIPPED.exec(line)
    return skipped ? [key(skipped[1] ?? '', skipped[2] ?? '')] : []
  })
}

/** A crash's summary, from the crash log the result bundle attached to the test. */
async function crashOf($: EngineInterface, bundle: string, test: string): Promise<string[] | undefined> {
  const made = await $.process.run(['mktemp', '-d'], {}).catch(() => undefined)
  const folder = made?.stdout.trim()
  if (!folder) return undefined
  try {
    await $.process.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', bundle, '--output-path', folder, '--test-id', `${test}()`, '--only-failures'], { timeoutMs: 15_000 })
    const log = (await $.fs.list(folder)).find(entry => entry.name.endsWith('.ips'))
    if (!log) return undefined
    const text = await $.fs.read(`${folder}/${log.name}`)
    return typeof text === 'string' ? crashSummaryOf(text) : undefined
  } finally {
    await $.process.run(['rm', '-rf', folder], {}).catch(() => undefined)
  }
}

async function details($: EngineInterface, bundle: string, test: string): Promise<string> {
  // The result bundle names a test with its `()`.
  const ran = await $.process
    .run(['xcrun', 'xcresulttool', 'get', 'test-results', 'test-details', '--test-id', `${test}()`, '--path', bundle, '--compact'], { timeoutMs: 15_000 })
    .catch(() => undefined)
  return ran?.stdout ?? ''
}

/** How many tests the run's summary line counts as skipped. */
function skippedCountOf(text: string): number {
  return Number(/^(?:❌|✅) \d+ tests? .*?(\d+) skipped/m.exec(text)?.[1] ?? 0)
}

/** The run's skipped tests, from the result bundle: MobileBuildMCP's list can leave one out. */
async function skipsOf($: EngineInterface, bundle: string): Promise<Map<string, Skip>> {
  const ran = await $.process
    .run(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', bundle, '--compact'], { timeoutMs: 15_000 })
    .catch(() => undefined)
  return skippedTestsOf(ran?.stdout ?? '')
}

/** The failing run's text with what the result bundle adds, or the text as it was when it adds nothing. */
export async function locateFailures($: EngineInterface, text: string): Promise<string> {
  const failures = failuresIn(text).filter(failure => !failure.isLocated || failure.isCrash).slice(0, MOST_LOOKUPS)
  const isSkipping = skippedCountOf(text) > 0 || skippedIn(text).length > 0
  if (failures.length === 0 && !isSkipping) return text
  const home = await $.env.get('HOME')
  const bundle = home ? resultBundleOf(text, home) : undefined
  if (!bundle) return text
  const failureNotes = new Map<string, string[]>()
  for (const failure of failures) {
    const notes: string[] = []
    if (!failure.isLocated) {
      const location = sourceLocationOf(await details($, bundle, failure.test))
      if (location) notes.push(`    ${location}`)
    }
    if (failure.isCrash) notes.push(...((await crashOf($, bundle, failure.test)) ?? []).map(line => `      ${line}`))
    if (notes.length > 0) failureNotes.set(failure.test, notes)
  }
  const skips = isSkipping ? await skipsOf($, bundle) : new Map<string, Skip>()
  const reasonOf = (skip: Skip): string[] => (skip.reason ? [`      skipped: ${skip.reason}`] : [])
  const listed = new Set(skippedIn(text))
  const skipNotes = new Map([...skips].filter(([test]) => listed.has(test)).map(([test, skip]) => [test, reasonOf(skip)]))
  const unlisted = [...skips]
    .filter(([test]) => !listed.has(test))
    .slice(0, MOST_LOOKUPS)
    .flatMap(([test, skip]) => [`  ⏭️ ${test}() (${skip.seconds.toFixed(3)}s)`, ...reasonOf(skip)])
  if (failureNotes.size === 0 && [...skipNotes.values()].every(notes => notes.length === 0) && unlisted.length === 0) return text
  return annotate(text, { failures: failureNotes, skipped: skipNotes, unlisted })
}

/**
 * A note naming a run's expected failures (`XCTExpectFailure`), from `xcresulttool get test-results
 * summary`: MobileBuildMCP's counts leave them out, so passed + failed + skipped falls short of the
 * tests that ran. Undefined when there are none.
 */
export function expectedFailuresNoteOf(summary: string): string | undefined {
  const counts = parse(summary) as { totalTestCount?: number; expectedFailures?: number } | undefined
  const expected = counts?.expectedFailures ?? 0
  if (expected === 0) return undefined
  const tests = expected === 1 ? '1 test also ran as an expected failure' : `${expected} tests also ran as expected failures`
  const total = counts?.totalTestCount !== undefined ? `: ${counts.totalTestCount} tests ran in all` : ''
  return `xcrew: ${tests} (XCTExpectFailure). They count as neither passed nor failed in the result${total}.`
}

/** The expected-failures note for a MobileBuildMCP test run, read from its result bundle. */
export async function expectedFailuresNote($: EngineInterface, text: string): Promise<string | undefined> {
  const home = await $.env.get('HOME')
  const bundle = home ? resultBundleOf(text, home) : undefined
  if (!bundle) return undefined
  const ran = await $.process.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', bundle, '--compact'], { timeoutMs: 15_000 }).catch(() => undefined)
  return ran ? expectedFailuresNoteOf(ran.stdout) : undefined
}
