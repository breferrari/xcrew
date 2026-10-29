import { expect, mock, test } from 'claude-code/testing'
import { callTool, runCommand, stubCli } from './testing'

test('a build whose call fails underneath stops counting', async ($, on) => {
  const clock = mock.clock(on)
  stubCli(on)
  const statuses: (string | undefined)[] = []
  on('ui.status', (_, e) => {
    statuses.push(e.text)
    return { value: undefined }
  })
  on('tool.call', async () => {
    await clock.advance(2_000)
    throw new Error('interrupted')
  })

  await callTool($, 'mcp__plugin_xcrew_MobileBuildMCP__build_sim').catch(() => undefined)
  const counted = statuses.length
  await clock.advance(5_000)

  expect(statuses.length).toBe(counted)
  expect(statuses.at(-1)).toBeUndefined()
})

test('/xcrew says when it couldn\'t answer', async ($, on) => {
  on('store.keys', () => {
    throw new Error('store unavailable')
  })

  const answer = await runCommand($, 'xcrew', 'history')

  expect(answer.text).toMatch(/^\/xcrew history couldn't answer: /)
})
