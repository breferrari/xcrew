import type { Register } from 'claude-code'
import { registerBand } from './band'
import { registerCommand } from './command'
import { registerFailures } from './failures'
import { registerSession } from './session'
import { registerGuard } from './guard'
import { registerRepair } from './repair'
import { registerTiming } from './timing'

/**
 * xcrew's mod. Hooks on one event run in the order registered, each wrapping the ones after it:
 * the guard refuses before anything starts, timing covers a repair's retry, and the repair sits
 * closest to the tool.
 */
export const register: Register = on => {
  registerGuard(on)
  registerTiming(on)
  registerRepair(on)
  registerBand(on)
  registerCommand(on)
  registerFailures(on)
  registerSession(on)
}
