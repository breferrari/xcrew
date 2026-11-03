import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'
import { callTool, stubCli, type CliCall } from './testing'

const TOOL = 'mcp__xcrew__affected'

/** A session whose CLI answers `xcrew affected` with `answer`, or fails when it's an Error. Records the registered tools. */
function session(on: On, answer: unknown) {
  mock.store(on)
  const registered: { name: string; isDeferred?: unknown }[] = []
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => {
    registered.push({ name: e.name, isDeferred: e.isDeferred })
    return { value: { tool: `mcp__xcrew__${e.name}` } }
  })
  const calls: CliCall[] = stubCli(on, {
    affected: () => {
      if (answer instanceof Error) throw answer
      return answer
    },
  })
  on('tool.call', () => ({ result: {}, text: 'done' }))
  return { registered, calls }
}

const ask = async (tool: Engine, input: Record<string, unknown> = {}) => String((await callTool(tool, TOOL, input)).result ?? '')

/** `count` targets named `prefix` and a number, in order: `U01`, `U02`, … */
const named = (prefix: string, count: number) => Array.from({ length: count }, (_, index) => `${prefix}${String(index + 1).padStart(2, '0')}`)
const ALL = 'all of them: `xcrew affected` in Bash, or `!xcrew affected` at the prompt'

test('Claude finds the affected tool behind ToolSearch, registered beside the ledger', async ($, on) => {
  const seen = session(on, {})
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  expect(seen.registered).toContainEqual({ name: 'affected', isDeferred: undefined })
})

test('a selection names the test targets and the -only-testing arguments that run them, with the base', async ($, on) => {
  session(on, { base: 'origin/main, from 0123456789ab', changed: ['Core/Store.swift'], selections: ['AppTests', 'CoreTests'] })
  const text = await ask($)
  expect(text).toStartWith('The changes can break 2 test targets: AppTests, CoreTests')
  expect(text).toContain('-only-testing:AppTests -only-testing:CoreTests')
  expect(text).toContain('origin/main, from 0123456789ab')
})

test('each scheme that tests only selected targets is named with its own targets, and so is what none of them tests', async ($, on) => {
  session(on, { changed: ['Modules/Feature/Sources/Feature.swift'], selections: ['AppTests', 'AppUITests', 'CoreTests', 'FeatureTests'], schemes: [{ name: 'Feature', container: 'Modules/Feature/Feature.xcodeproj', targets: ['FeatureTests'] }, { name: 'App', container: 'Modules/App/App.xcodeproj', targets: ['AppTests', 'AppUITests'] }] })
  expect(await ask($)).toContain(' Schemes that test only selected targets: `Feature` (FeatureTests) and `App` (AppTests, AppUITests). No shared scheme tests CoreTests.')
})

test('schemes that between them test every selected target are said to', async ($, on) => {
  session(on, { changed: ['Feature.swift'], selections: ['FeatureTests'], schemes: [{ name: 'Feature', container: 'App.xcworkspace', targets: ['FeatureTests'] }] })
  expect(await ask($)).toContain(' Schemes that test only selected targets: `Feature` (FeatureTests). Between them they test every selected target.')
})

test('schemes of one name are told apart by their container', async ($, on) => {
  session(on, { changed: ['A.swift'], selections: ['ATests', 'BTests'], schemes: [{ name: 'Tests', container: 'A.xcodeproj', targets: ['ATests'] }, { name: 'Tests', container: 'B.xcodeproj', targets: ['BTests'] }] })
  expect(await ask($)).toContain('`Tests` in A.xcodeproj (ATests) and `Tests` in B.xcodeproj (BTests)')
})

test('without such schemes no scheme is named', async ($, on) => {
  session(on, { changed: ['Core/Store.swift'], selections: ['AppTests', 'CoreTests'] })
  expect(await ask($)).not.toContain('Schemes that test')
})

test('when nothing narrower can be said, it names the whole suite with the reason', async ($, on) => {
  session(on, { base: 'origin/main, from 0123456789ab', changed: ['Package.resolved'], runAll: 'Package.resolved changes what the build does in a way this doesn\'t read' })
  const text = await ask($)
  expect(text).toStartWith('No narrower selection: Package.resolved changes what the build does')
  expect(text).toContain('the whole suite covers the changes')
  expect(text).toContain('Package.resolved changes what the build does')
})

test('when the CLI can\'t answer, the answer is the whole suite', async ($, on) => {
  session(on, new Error('timed out'))
  expect(await ask($)).toStartWith("xcrew couldn't say which tests the changes can break; the whole suite covers them.")
})

test('when the CLI can\'t answer, the answer says why', async ($, on) => {
  session(on, new Error('timed out'))
  expect(await ask($)).toMatch(/the whole suite covers them\. xcrew affected couldn't run: ./)
})

test('a base Claude names is passed to the CLI', async ($, on) => {
  const seen = session(on, { base: 'release/2.0, from fedcba987654', changed: [], selections: [] })
  await ask($, { base: 'release/2.0' })
  expect(seen.calls.find(call => call.args[0] === 'affected')?.args).toEqual(['affected', '--base', 'release/2.0'])
})

test('changed files no test target covers are said to be changed, not missing', async ($, on) => {
  session(on, { base: 'origin/main, from 0123456789ab', changed: ['Widget/Timeline.swift'], selections: [] })
  const text = await ask($)
  expect(text).toContain('1 changed file')
  expect(text).not.toContain('Nothing has changed')
})

test('without a base the answer names none', async ($, on) => {
  session(on, { runAll: "this isn't a git repository, so the change can't be told apart" })
  expect(await ask($)).not.toContain('Compared with')
})

test('session start registers exactly the ledger, affected, look and evidence tools, once each', async ($, on) => {
  const seen = session(on, {})
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  expect(seen.registered).toEqual([{ name: 'ledger', isDeferred: undefined }, { name: 'affected', isDeferred: undefined }, { name: 'look', isDeferred: undefined }, { name: 'evidence', isDeferred: undefined }])
})

/** A large selection, as a big modular app's: the count first, by what runs them, a few names of each, the rest counted. */
test('a large selection says its count first, by kind, and names a few of each', async ($, on) => {
  const unit = named('U', 25), ui = named('UI', 3)
  session(on, { changed: ['Core/Store.swift'], selections: [...unit, ...ui].sort(), uiSelections: ui })
  const text = await ask($)
  expect(text).toStartWith('The changes can break 28 test targets, 25 unit and 3 UI.')
  expect(text).toContain(`Unit: ${unit.slice(0, 10).join(', ')} and 15 more; ${ALL}.`)
  expect(text).not.toContain('-only-testing:U01')
  expect(text).toContain('UI: UI01, UI02, UI03 (-only-testing:UI01 -only-testing:UI02 -only-testing:UI03).')
})

/** Up to 20 targets of a kind, the arguments that run them are given; past that, the list is too long to use. */
test('the -only-testing arguments are given for up to 20 targets of a kind', async ($, on) => {
  session(on, { changed: ['Core/Store.swift'], selections: named('U', 20) })
  expect(await ask($)).toContain('-only-testing:U20')
})

test('past 20 targets of a kind, no arguments are given', async ($, on) => {
  session(on, { changed: ['Core/Store.swift'], selections: named('U', 21) })
  const text = await ask($)
  expect(text).not.toContain('-only-testing:')
  expect(text).toContain(`and 11 more; ${ALL}.`)
})

/** A scheme with many targets is counted, as is what none of the schemes tests. */
test('a scheme of many targets is counted rather than listed', async ($, on) => {
  const unit = named('U', 30)
  session(on, { changed: ['Core/Store.swift'], selections: unit, schemes: [{ name: 'Feature', container: 'App.xcworkspace', targets: unit.slice(0, 15) }] })
  expect(await ask($)).toContain(` Schemes that test only selected targets: \`Feature\` (15 targets; ${ALL}). No shared scheme tests 15 of the selected targets; ${ALL}.`)
})

/** Most of the suite: the CLI names the scheme that tests all of it, and no other is listed. */
test('when the changes reach most of the suite, the scheme that tests all of it is named alone', async ($, on) => {
  const all = ['AppTests', 'AppUITests', 'CoreTests', 'DataTests', 'FeatureTests']
  session(on, { changed: ['Core.swift'], selections: all, whole: { name: 'Everything', container: 'Field.xcworkspace', tests: all, others: [] } })
  const text = await ask($)
  expect(text).toEndWith(' The changes reach most of the suite: `Everything` tests every selected target.')
  expect(text).not.toContain('Schemes that test')
})

test('the scheme that tests most of the suite names the targets it tests beyond it', async ($, on) => {
  const all = ['AppTests', 'CoreTests', 'FeatureTests']
  session(on, { changed: ['Core.swift'], selections: all, whole: { name: 'App-Workspace', container: 'App.xcworkspace', tests: all, others: ['DataTests', 'UITests'] } })
  expect(await ask($)).toEndWith(' The changes reach most of the suite: `App-Workspace` tests every selected target, and DataTests and UITests besides.')
})

/** A target no listed scheme tests is named with the scheme that tests it with the fewest more, as the CLI chose it. */
test('a selected target no listed scheme tests is named with the scheme that tests it with a few more', async ($, on) => {
  session(on, {
    changed: ['Feature.swift'],
    selections: ['AppUITests', 'FeatureTests'],
    schemes: [{ name: 'Feature', container: 'Modules/Feature/Feature.xcodeproj', targets: ['FeatureTests'] }],
    nearest: [{ name: 'Mixed', container: 'Field.xcworkspace', tests: ['AppUITests'], others: ['AppTests'] }],
  })
  expect(await ask($)).toEndWith(' Schemes that test only selected targets: `Feature` (FeatureTests). `Mixed` tests AppUITests, and AppTests besides.')
})

/** Many schemes are capped as many targets are: the first named, the rest counted, and where they all are. */
test('many schemes are capped, the rest counted', async ($, on) => {
  const unit = named('U', 12)
  session(on, { changed: ['Core.swift'], selections: unit, schemes: unit.map(target => ({ name: target, container: 'App.xcworkspace', targets: [target] })) })
  expect(await ask($)).toContain(` Schemes that test only selected targets: ${unit.slice(0, 10).map(target => `\`${target}\` (${target})`).join(', ')} and 2 more; ${ALL}. Between them they test every selected target.`)
})
