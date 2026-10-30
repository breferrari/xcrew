import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'
import { callTool, stubCli, type CliCall } from './testing'

const PBXPROJ = '/work/App/ios/App.xcodeproj/project.pbxproj'
const MANIFEST = 'ios/Project.swift'
const GENERATE = 'tuist generate --no-open --path ios'

/**
 * A Tuist project where the CLI says `PBXPROJ` is generated from `MANIFEST`. The person answers the question with `pick`:
 * an option's label, free text, or nobody there to ask. Records the questions asked and the calls that ran.
 */
function generatedProject(on: On, pick: (options: string[]) => string | 'nobody') {
  mock.store(on)
  const asked: { question: string; options: string[] }[] = []
  const ran: string[] = []
  const cli: CliCall[] = stubCli(on, {
    project: args => ({
      isGenerated: true,
      ...(args.includes('--generated') && args.includes(PBXPROJ) ? { manifest: MANIFEST, generate: GENERATE, app: 'ios' } : {}),
    }),
  })
  on('tool.call', (_, e) => {
    if (e.tool === 'AskUserQuestion') {
      const question = e.questions[0]
      const options = question?.options.map(option => option.label) ?? []
      asked.push({ question: question?.question ?? '', options })
      const answer = pick(options)
      if (answer === 'nobody') return { deny: 'There is no one to ask in this session.' }
      return { result: { questions: e.questions, answers: { [question?.question ?? '']: answer } } }
    }
    ran.push(e.tool)
    return { result: {}, text: 'done' }
  })
  return { asked, ran, cli }
}

const editPbxproj = (tool: Engine) => callTool(tool, 'Edit', { file_path: PBXPROJ, old_string: 'a', new_string: 'b' })

test('an edit to a generated file asks the person first, and runs when they say so', async ($, on) => {
  const seen = generatedProject(on, options => options[0] ?? '')
  const edited = await editPbxproj($)
  expect(edited.deny).toBeUndefined()
  expect(seen.ran).toEqual(['Edit'])
  expect(seen.asked).toHaveLength(1)
  expect(seen.asked[0]?.question).toContain(GENERATE)
  expect(seen.asked[0]?.options[1]).toContain(MANIFEST)
})

test('choosing the manifest instead refuses the edit, naming the manifest and the command', async ($, on) => {
  const seen = generatedProject(on, options => options[1] ?? '')
  const edited = await callTool($, 'Write', { file_path: PBXPROJ, content: '' })
  expect(edited.deny).toContain(MANIFEST)
  expect(edited.deny).toContain(`\`${GENERATE}\``)
  expect(seen.ran).toEqual([])
})

test('what the person types instead of choosing reaches Claude with the refusal', async ($, on) => {
  generatedProject(on, () => 'only the scheme, please')
  const edited = await editPbxproj($)
  expect(edited.deny).toContain('only the scheme, please')
})

test('with nobody to ask, the edit is refused with the reason, as before', async ($, on) => {
  const seen = generatedProject(on, () => 'nobody')
  const edited = await editPbxproj($)
  expect(edited.deny).toContain(MANIFEST)
  expect(seen.ran).toEqual([])
})

test('a file no generator writes is edited without a question, and only a generated name is asked about', async ($, on) => {
  const seen = generatedProject(on, options => options[0] ?? '')
  // A source file named like a manifest, as in the test bed's trap, and a plain source file.
  for (const file of ['/work/App/ios/App/Models/Project.swift', '/work/App/ios/App/ContentView.swift', '/work/App/ios/Other.xcodeproj/project.pbxproj']) {
    expect((await callTool($, 'Edit', { file_path: file, old_string: 'a', new_string: 'b' })).deny).toBeUndefined()
  }
  expect(seen.asked).toEqual([])
  expect(seen.cli.filter(call => call.args.includes('--generated')).map(call => call.args.at(-1))).toEqual(['/work/App/ios/Other.xcodeproj/project.pbxproj'])
})

test('when the CLI can\'t answer, the edit goes through', async ($, on) => {
  mock.store(on)
  on('process.run', () => {
    throw new Error('xcrew not built')
  })
  on('tool.call', () => ({ result: {}, text: 'done' }))
  expect((await editPbxproj($)).deny).toBeUndefined()
})

test('XcodeWrite in a generated project asks too: yes runs it, the alternative refuses it with Write named', async ($, on) => {
  let choice = 0
  const seen = generatedProject(on, options => options[choice] ?? '')
  for (const tool of ['mcp__xcode__XcodeWrite', 'mcp__plugin_xcrew_xcode__XcodeWrite']) {
    choice = 0
    expect((await callTool($, tool, { filePath: 'App/New.swift', content: '' })).deny).toBeUndefined()
    choice = 1
    expect((await callTool($, tool, { filePath: 'App/New.swift', content: '' })).deny).toContain('Write tool')
  }
  expect(seen.ran).toEqual(['mcp__xcode__XcodeWrite', 'mcp__plugin_xcrew_xcode__XcodeWrite'])
  expect(seen.asked).toHaveLength(4)
})

test('XcodeWrite with nobody to ask is refused, as before', async ($, on) => {
  generatedProject(on, () => 'nobody')
  expect((await callTool($, 'mcp__xcode__XcodeWrite', { filePath: 'App/New.swift', content: '' })).deny).toContain('Write tool')
})
