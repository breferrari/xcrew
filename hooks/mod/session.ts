import type { On } from 'claude-code'
import { COMMAND } from './command'
import { loadProblems } from './problems'

/** The one unmatched session start hook: offers `/xcrew`, and looks for problems without holding the session up. */
export function registerSession(on: On): void {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await $.command.register(COMMAND)
    void loadProblems($).catch(() => undefined)
    return started
  })
}
