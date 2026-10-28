import type { Register } from 'claude-code'
import { registerBand } from './band'
import { registerCommand } from './command'
import { registerFailures } from './failures'
import { registerSession } from './session'
import { registerGuard } from './guard'
import { registerTiming } from './timing'

/**
 * xcrew's mod. Hooks on one event run in the order registered, each wrapping the ones after it:
 * the guard refuses before anything starts, so timing never counts a refused call.
 */
export const register: Register = on => {
  registerGuard(on)
  registerTiming(on)
  registerBand(on)
  registerCommand(on)
  registerFailures(on)
  registerSession(on)
}
