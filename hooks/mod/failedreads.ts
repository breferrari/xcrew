import { readKey, type Problem } from './cli'
import { visible, WARNING_FOR_MS } from './problems'
import { withContext } from './timing'

/** How a read went changed what the band shows: it answered after failing, or it failed for the first time. */
export type ReadChange = 'answered' | 'new'

/**
 * The CLI reads that failed, as Claude is told them and the band shows them. A failure of a read a call waits on is said
 * each time, as that call goes without its fact; one nobody waits on, as the band's, is said once until it answers.
 * Either shows on the band as a warning does, from when it first failed; an answer takes it back from both.
 */
export class FailedReads {
  /** The reads whose last try failed and no result has said yet, by `readKey`: each said once. */
  private readonly unsaid = new Map<string, string>()
  /**
   * The reads nobody waits on whose failure was said, by `saidName`: the read by `readKey`, so `runs --overlapped --since
   * … --until …` is one read across runs, and the failure's own line, so a different failure is said too. Each goes once
   * its read answers.
   */
  private readonly said = new Set<string>()
  /**
   * The reads whose last try failed, by `readKey`, as the band shows them; when each first failed, by its id; and when it
   * last did. One that hasn't failed again for a warning's time is dropped.
   */
  private readonly failing = new Map<string, Problem>()
  private failedAt: Record<string, number> = {}
  private readonly lastFailedAt = new Map<string, number>()

  /** Records how a read of `question` went at `at`: what that changes on the band, if anything. */
  went(question: string, failed: string | undefined, at: number | undefined, waited: boolean): ReadChange | undefined {
    const read = readKey(question)
    const id = `xcrew/read ${read}`
    if (failed === undefined) {
      this.unsaid.delete(read)
      for (const said of [...this.said]) if (said.startsWith(`${read}\n`)) this.said.delete(said)
      delete this.failedAt[id]
      this.lastFailedAt.delete(read)
      return this.failing.delete(read) ? 'answered' : undefined
    }
    const isNew = !this.failing.has(read)
    this.failing.set(read, { status: 'warn', id, message: failed })
    if (at !== undefined) this.lastFailedAt.set(read, at)
    const said = saidName(question, failed)
    if (waited || !this.said.has(said)) this.unsaid.set(read, failed)
    if (!waited) this.said.add(said)
    if (!isNew) return undefined
    // Without the time, its time on the band is taken as over.
    this.failedAt[id] = at ?? Number.NEGATIVE_INFINITY
    return 'new'
  }

  /**
   * The failed reads the band shows at `now`, as a warning shows, for its first few minutes. One kept failing stays
   * recorded, hidden, so it isn't new again; one that hasn't failed again for that long goes, as a read whose arguments
   * name a moment or a file may never be asked again.
   */
  shown(now: number): Problem[] {
    for (const [read, problem] of this.failing) {
      if (now - (this.lastFailedAt.get(read) ?? Number.NEGATIVE_INFINITY) < WARNING_FOR_MS) continue
      this.failing.delete(read)
      this.lastFailedAt.delete(read)
      delete this.failedAt[problem.id]
    }
    return visible([...this.failing.values()], this.failedAt, now)
  }

  /** The failed reads no result has said yet, taken to be said now. */
  take(): string[] {
    const lines = [...this.unsaid.values()]
    this.unsaid.clear()
    return lines
  }

  /** A command's text with the failed reads no result has said yet after it. */
  withText(text: string): string {
    return [text, ...this.take()].join('\n')
  }

  /** A result of xcrew's tools with the failed reads not said yet; a refused call leaves them to the next. */
  withResult<Result extends { deny?: unknown; context?: readonly string[] }>(result: Result): Result {
    if (result.deny !== undefined || this.unsaid.size === 0) return result
    return withContext(result, ...this.take())
  }

  /** Forgets them all: the conversation before's failed reads were its own. */
  clear(): void {
    this.unsaid.clear()
    this.said.clear()
    this.failing.clear()
    this.failedAt = {}
    this.lastFailedAt.clear()
  }
}

/** A background read's failure as it's said once: the read by `readKey`, then the failure's line. */
function saidName(question: string, failed: string): string {
  const read = readKey(question)
  // The failure's line names the read: by its moments too, which are left out of it here.
  return `${read}\n${failed.replaceAll(question, read)}`
}
