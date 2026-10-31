import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Report } from './cli'
import { callTool, stubCli } from './testing'

/** A passing build whose log holds `count` concurrency diagnostics, with the note the CLI words for them. */
function built(count: number): Partial<Report> {
  return { ok: true, detail: 'build succeeded', failures: [], notes: [], concurrency: { count, note: `xcrew: this build's log has ${count} Swift concurrency diagnostics in 2 modules. \`xcrew concurrency\` lists them by compiler group and module.` } }
}

function session(on: On, reports: Partial<Report>[]) {
  mock.clock(on)
  mock.store(on)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.surfaces', () => ({ value: ['terminal'] }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('tool.register', (_, e) => ({ value: { tool: `mcp__xcrew__${e.name}` } }))
  stubCli(on, { reports })
  on('tool.call', () => ({ result: {}, text: 'the server\'s result' }))
}

/** What Claude reads after a MobileBuildMCP build of `scheme`. */
const build = async ($: Parameters<typeof callTool>[0], scheme = 'App', tool = 'build_sim', input: Record<string, unknown> = {}) =>
  ((await callTool($, `mcp__MobileBuildMCP__${tool}`, { scheme, ...input })).context ?? []) as string[]

const said = (context: string[]) => context.filter(line => line.includes('Swift concurrency diagnostics'))

test('the counts ride on the first build that has many, and not again for the same scheme', async ($, on) => {
  session(on, [built(40), built(40)])
  expect(said(await build($))).toHaveLength(1)
  expect(said(await build($))).toHaveLength(0)
})

/** An incremental build logs only what it recompiled: a lower count is the log's, not the code's. */
test('it is given again only on a rise of a quarter over the highest given: 40 given, 12 silent, 40 silent, 50 given', async ($, on) => {
  session(on, [built(40), built(12), built(40), built(50)])
  expect(said(await build($))).toHaveLength(1)
  expect(said(await build($))).toHaveLength(0)
  expect(said(await build($))).toHaveLength(0)
  expect(said(await build($))).toHaveLength(1)
})

test('another scheme, or a new session, is given its own', async ($, on) => {
  session(on, [built(40), built(40), built(40)])
  await build($, 'App')
  expect(said(await build($, 'Kit'))).toHaveLength(1)
  await $.session.start({ cwd: '/work/App', surface: 'terminal', isInteractive: true })
  expect(said(await build($, 'App'))).toHaveLength(1)
})

/** A test run builds the scheme too, and its log holds the same diagnostics: the scheme's note isn't given twice. */
test('a build and a test run of one scheme, or two selections, are one scheme', async ($, on) => {
  session(on, [built(40), built(40), built(40)])
  expect(said(await build($, 'App'))).toHaveLength(1)
  expect(said(await build($, 'App', 'test_sim'))).toHaveLength(0)
  expect(said(await build($, 'App', 'test_sim', { extraArgs: ['-only-testing:AppTests/One'] }))).toHaveLength(0)
})
