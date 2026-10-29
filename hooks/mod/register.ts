import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'
import type { BandProblems, BandRun, CliBuild, FailureList } from '../../types'
import { changedRun, endedRun, outcomeLine, problemsTree, runTree, shownFor, showsRun } from './band'
import { answerOf, couldntRun, isGeneratedOf, knownBuild, namedBuild, phaseArgs, phaseOf, problemsOf, ranOutOfTime, reportArgs, reportOf, shimPath, type Failure, type Problem, type Ran } from './cli'
import { COMMAND, historyText, isStale, keptHistory, USAGE } from './command'
import { describe, historyOf, observe } from './context'
import { afterRun, paneTree, summary } from './failures'
import { average } from './format'
import { describedForGenerated, REASON } from './guard'
import { mostSerious, noticed, REREAD_EVERY_MS, visible, WARNING_FOR_MS } from './problems'
import { DURATIONS_PREFIX, drawsBand, endingOf, type Following, historyKey, HISTORY, labelOf, LONG_RUN_MS, logsKey, phaseStep, quietly, resultFor, statusLine, testsKey, updatedKey } from './timing'
import { kindOf, parseTool, PROJECT_REWRITER, runsSetup } from './tools'

// The mod's state, which the loader reads only from atoms declared in the hooks module itself.
const runState = atom({ plugin: 'xcrew', key: 'run' } as const, null as BandRun | null)
const failuresState = atom({ plugin: 'xcrew', key: 'failures' } as const, null as FailureList | null)
const problemsState = atom({ plugin: 'xcrew', key: 'problems' } as const, null as BandProblems | null)
/** The failures pane's id: a literal here, so the loader can read the pane hook's matcher. */
const FAILURES_PANE = 'xcrew-failures'
/** The shim's last answer, for the session: the build to run, or none. */
const buildState = atom({ plugin: 'xcrew', key: 'build' } as const, null as CliBuild | null)

/**
 * xcrew's mod: the only file that touches `$` or registers a hook. The plugin directory reads `$`
 * only where a hooks module passes it, whole, to a function declared at the top of the same file,
 * so every `$` call is here and every other file is plain data in, data out. docs/architecture.md
 * has the rule and the docs it comes from.
 *
 * Hooks on one event run in the order registered, each wrapping the ones after it: the guard
 * refuses before anything starts, so timing never counts a refused call.
 */
export const register: Register = on => {
  // The two tool.call hooks fail open, as the engine would without a handler; it's stated so validate reads it, and so
  // a later change can't turn either into a refusal by accident. Nothing below them throws today.
  on('tool.call', { tool: PROJECT_REWRITER }, async ($, e, next) => ((await isGeneratedProject($)) ? { deny: REASON } : next(e))).catch(async ($, e, next) => next(e))
  on('tool.describe', { tool: PROJECT_REWRITER }, async ($, e, next) => {
    const described = await next(e)
    return (await isGeneratedProject($)) ? { ...described, description: describedForGenerated(described.description) } : described
  })
  on('tool.call', async ($, e, next) => {
    const parsed = parseTool(e.tool)
    if (!parsed) return next(e)
    const name = parsed.tool
    const kind = kindOf(parsed)
    if (!kind) {
      // Not timed, but its answer may say what the next build will use.
      const result = await next(e)
      observe(parsed, result.text ?? '')
      return result
    }
    const target = describe(parsed, e as unknown as Record<string, unknown>)
    const label = labelOf(name, target)
    // Durations and test totals are kept per scheme and test selection, not only per tool.
    const scope = historyOf(parsed, e as unknown as Record<string, unknown>)

    const started = await quietly(() => $.clock.now())
    const stored = ((await quietly(() => $.store.get(historyKey(scope)))) as number[] | undefined) ?? []
    const updated = await quietly(() => $.store.get(updatedKey(scope)))
    // Runs from weeks ago say nothing about this one: they don't count, and this run starts the line afresh.
    const earlier = started !== undefined && isStale(updated, started) ? [] : stored
    // What the gauge measures against; a tool's first run has none and shows its time alone.
    const usual = earlier.length > 0 ? average(earlier) : undefined
    const usesBand = drawsBand((await quietly(() => $.session.surfaces())) ?? [])
    // MobileBuildMCP logs xcodebuild's output as the run goes; the Xcode MCP writes nothing to follow.
    const followsLog = parsed.server === 'MobileBuildMCP'
    const expectedTests = followsLog ? ((await quietly(() => $.store.get(testsKey(scope)))) as number | undefined) : undefined
    const writesLog = followsLog && (await quietly(() => $.store.get(logsKey(name)))) === true
    // The usual time is the server's own, which leaves out a pre-build hook; for a tool that logs,
    // the gauge starts when the log appears, before which the run itself hasn't begun.
    let measuredFrom = writesLog ? undefined : started
    let following: Following = {}
    if (usesBand && started !== undefined) await quietly(() => startRun($, { tool: name, target, startedAt: started, ...(usual === undefined ? {} : { usual }), ...(measuredFrom === undefined ? {} : { measuredFrom }) }))
    const readPhase = async (since: number) => {
      const found = (await quietly(() => runPhase($, name, since, expectedTests, following.logPath))) ?? {}
      const step = phaseStep(following, found, writesLog)
      following = step.following
      if (step.logAppeared) {
        if (!writesLog) await quietly(() => $.store.set(logsKey(name), true))
        if (measuredFrom === undefined) {
          measuredFrom = await quietly(() => $.clock.now())
          const from = measuredFrom
          if (usesBand && from !== undefined) await quietly(() => update($, runState, run => changedRun(run, { measuredFrom: from })))
        }
      }
      const shown = step.newPhase
      if (usesBand && shown !== undefined) await quietly(() => update($, runState, run => changedRun(run, { phase: shown })))
    }
    const ticker = started === undefined ? undefined : await quietly(() =>
      $.clock.every(1000, async () => {
        if (followsLog) await readPhase(started)
        if (usesBand) return quietly(() => $.ui.invalidate('ui.render'))
        const now = await quietly(() => $.clock.now())
        if (now !== undefined) await quietly(() => $.ui.status(statusLine(label, started, now, measuredFrom, usual, following.phase)))
      }),
    )

    // However the call ends, the run stops counting; one that failed beneath leaves the band too.
    const result = await next(e)
      .catch(async (error: unknown) => {
        if (usesBand) await quietly(() => update($, runState, () => null))
        throw error
      })
      .finally(async () => {
        ticker?.cancel()
        if (!usesBand) await quietly(() => $.ui.status(undefined))
      })
    const ended = await quietly(() => $.clock.now())
    if (started === undefined || ended === undefined) return result
    // A denied call never ran: it has no outcome to show and no time that says how long a run takes.
    if (result.deny !== undefined) {
      if (usesBand) await quietly(() => update($, runState, () => null))
      return result
    }

    // The CLI reads the server's output: the outcome, the failures, the duration it reports, and what Claude reads.
    // It never throws: without the CLI it falls back to whether the server reported an error.
    const outcome = reportOf(await answer($, reportArgs(parsed.server, kind, result.isError === true), 120_000, result.text ?? ''), result.isError === true)
    // The server's own duration leaves out what ran around the call: a project's pre-build hook, a permission prompt.
    const elapsed = outcome.durationMs ?? ended - started
    await quietly(() => $.store.set(historyKey(scope), [...earlier, elapsed].slice(-HISTORY)))
    await quietly(() => $.store.set(updatedKey(scope), ended))
    await quietly(() => recordRun($, scope, outcome.ok, outcome.failures))
    if (outcome.tests !== undefined) await quietly(() => $.store.set(testsKey(scope), outcome.tests))
    const ending = endingOf(outcome, ended, elapsed, earlier)
    const summaryLine = outcomeLine(name, ending)
    if (usesBand) {
      await quietly(() => update($, runState, run => endedRun(run, ending)))
      // The outcome leaves the band on its own; a later run has replaced it by then, or it's this one.
      await quietly(() => $.clock.after(shownFor(ending) + 1, () => void quietly(() => update($, runState, run => (run?.ended?.at === ending.at ? null : run)))))
    } else {
      // The band stays up with this same line where it draws; elsewhere a toast carries it.
      await quietly(() => $.ui.toast(summaryLine))
    }
    // Long enough that the person has likely looked away; their notification settings decide how it arrives.
    if (elapsed >= LONG_RUN_MS) await quietly(() => $.ui.notify(summaryLine))
    return resultFor(result, outcome)
  }).catch(async ($, e, next) => next(e))
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const run = await read($, runState)
    const now = await $.clock.now()
    // A run going has the band; then the restart, which fixes most of what a finished run or a problem shows.
    if (run && !run.ended) return runTree($.ui.resolve(e), run, now)
    const problems = await read($, problemsState)
    if (problems?.isRestart) return problemsTree($.ui.resolve(e), problems)
    if (showsRun(run, now)) return runTree($.ui.resolve(e), run, now)
    return problems ? problemsTree($.ui.resolve(e), problems) : next(e)
  })
  on('command.run', { command: 'xcrew' }, async ($, e) => {
    const subcommand = (e.args ?? '').trim()
    if (subcommand === 'doctor') return { text: await cliText($, ['doctor']) }
    if (subcommand === 'history') return { text: await history($) }
    if (subcommand === 'failures') {
      await dismissFailedRun($)
      return { text: await openFailures($) }
    }
    if (subcommand === 'close') {
      await dismissFailedRun($)
      return { text: await closeFailures($) }
    }
    return { text: USAGE }
  }).catch(async ($, e, next) => ({ text: `/xcrew ${(e.args ?? '').trim()} couldn't answer: ${next.error?.message ?? 'it failed'}` }))
  on('ui.render', { component: 'Pane', requestId: FAILURES_PANE }, async ($, e) => paneTree($.ui.resolve(e), await read($, failuresState)))
  // The one unmatched session start hook: offers `/xcrew`, and looks for problems without holding the session up.
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await $.command.register(COMMAND)
    // A cleared conversation is a new session: its warnings show again.
    found = []
    seenAt = {}
    void loadProblems($).catch(() => undefined)
    return started
  })
  // The one unmatched prompt hook: a problem fixed any way at all leaves the band by the next prompt. Never awaited.
  on('prompt.submit', async ($, e, next) => {
    void (async () => {
      if (!drawsBand((await quietly(() => $.session.surfaces())) ?? [])) return
      if ((await $.clock.now()) - lastRead >= REREAD_EVERY_MS) await loadProblems($)
    })().catch(() => undefined)
    return next(e)
  })
  // Setup may have written the config: look at once whether MobileBuildMCP now needs a restart.
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const result = await next(e)
    if (e.tool === 'Bash' && runsSetup(e.command)) void loadProblems($, true).catch(() => undefined)
    return result
  }).catch(async ($, e, next) => next(e))
}

/** Starts a program of the CLI's: the mod's one process. */
function start($: EngineInterface, program: string, args: string[], timeoutMs: number, stdin?: string) {
  return $.process.run([program, ...args], { timeoutMs, env: { XCREW_ROOT: $.plugin.root }, ...(stdin === undefined ? {} : { stdin }) })
}

/** The question to the shim in flight, which callers at the same moment share rather than each starting a shim. */
let asking: Promise<string | undefined> | undefined

/**
 * The build the shim runs, asked for at most every 30 s, within the caller's own time: when the
 * shim must first build, a caller with ten seconds doesn't wait two minutes.
 */
async function build($: EngineInterface, timeoutMs: number): Promise<string | undefined> {
  const now = await $.clock.now()
  const known = knownBuild(await read($, buildState), now)
  if (known !== 'ask') return known
  asking ??= start($, shimPath($.plugin.root), ['--binary-path'], timeoutMs)
    .then(async ran => {
      const named = namedBuild(ran.stdout)
      await update($, buildState, () => ({ path: named, at: now }))
      return named ?? undefined
    })
    .finally(() => {
      asking = undefined
    })
  return asking
}

/**
 * Runs the CLI. The shim's own work is several times the build's, and the band asks once a second,
 * so the build it names runs directly. When the build can't be started, the shim runs instead; a
 * command that ran out of time isn't started again, which would double the wait.
 */
async function xcrew($: EngineInterface, args: string[], timeoutMs: number, stdin?: string): Promise<Ran> {
  const binary = await build($, timeoutMs).catch(() => undefined)
  if (binary) {
    const startedAt = await $.clock.now()
    try {
      return await start($, binary, args, timeoutMs, stdin)
    } catch (error) {
      if (ranOutOfTime(startedAt, await $.clock.now(), timeoutMs)) throw error
      await update($, buildState, () => null)
    }
  }
  return start($, shimPath($.plugin.root), args, timeoutMs, stdin)
}

/** The CLI's JSON answer, or nothing when it couldn't run or said something else. */
async function answer($: EngineInterface, args: string[], timeoutMs = 60_000, stdin?: string): Promise<unknown> {
  return answerOf(await xcrew($, args, timeoutMs, stdin).catch(() => undefined))
}

function runPhase($: EngineInterface, tool: string, since: number, expectedTests: number | undefined, log: string | undefined) {
  return answer($, phaseArgs(tool, since, expectedTests, log), 10_000).then(phaseOf)
}

async function isGeneratedProject($: EngineInterface): Promise<boolean> {
  return isGeneratedOf(await answer($, ['project'], 10_000))
}

/** A CLI command's own text, for `/xcrew doctor`, or why it couldn't run. */
function cliText($: EngineInterface, args: string[]): Promise<string> {
  return xcrew($, args, 120_000).then(ran => `${ran.stdout}${ran.stderr}`.trimEnd(), error => couldntRun(args, error))
}

/** A run has the band while it shows; the problems wait beneath it. */
function startRun($: EngineInterface, run: BandRun): Promise<unknown> {
  return update($, runState, () => run)
}

/** The doctor's last answer, and when each problem was first found: bookkeeping a reload may start over. */
let found: Problem[] = []
let seenAt: Record<string, number> = {}
let lastRead = Number.NEGATIVE_INFINITY

/** The doctor's run in flight, which a prompt meanwhile shares, so an older answer never lands after a newer one. */
let reading: Promise<void> | undefined

/** Asks the doctor what's wrong and keeps what the band shows, with a redraw when new warnings' time ends. */
function loadProblems($: EngineInterface, fresh = false): Promise<void> {
  // A read that began before setup wrote can't see what it wrote: wait for it, then read again.
  if (fresh && reading) return reading.catch(() => undefined).then(() => loadProblems($))
  reading ??= readProblems($).finally(() => {
    reading = undefined
  })
  return reading
}

async function readProblems($: EngineInterface): Promise<void> {
  const now = await $.clock.now()
  lastRead = now
  const answered = await answer($, ['doctor', '--problems', '--json'])
  // A doctor that couldn't run says nothing about what's fixed: the band stays as it was.
  if (answered === undefined) return
  found = problemsOf(answered)
  seenAt = noticed(found, seenAt, now)
  await showVisibleProblems($)
  // New warnings were all found now, so one redraw ends their time together.
  if (found.some(problem => problem.status === 'warn' && seenAt[problem.id] === now)) {
    await quietly(() => $.clock.after(WARNING_FOR_MS + 1, () => void quietly(() => showVisibleProblems($))))
  }
}

async function showVisibleProblems($: EngineInterface): Promise<void> {
  const now = await $.clock.now()
  await update($, problemsState, () => mostSerious(visible(found, seenAt, now)))
}

/** Looking at the failures, or closing them, takes the failed run off the band. */
async function dismissFailedRun($: EngineInterface): Promise<void> {
  await quietly(() => update($, runState, run => (run?.ended && !run.ended.ok ? null : run)))
}

async function recordRun($: EngineInterface, run: string, ok: boolean, items: Failure[]): Promise<void> {
  const list = await read($, failuresState)
  const after = afterRun(list, run, ok, items)
  if (after.list !== list) await update($, failuresState, () => after.list)
  if (after.closesPane) await $.ui.close({ id: FAILURES_PANE })
}

/** Opens the pane and says, in one line, what it holds. */
async function openFailures($: EngineInterface): Promise<string> {
  await $.ui.open({ id: FAILURES_PANE, title: 'Failures' })
  return summary(await read($, failuresState))
}

/** In Claude Code's default layout the pane's close mark can't be clicked; this closes it from the prompt. */
async function closeFailures($: EngineInterface): Promise<string> {
  await $.ui.close({ id: FAILURES_PANE })
  return 'Closed the failures pane.'
}

/** `/xcrew history`. */
async function history($: EngineInterface): Promise<string> {
  const tools = (await $.store.keys()).filter(key => key.startsWith(DURATIONS_PREFIX)).map(key => key.slice(DURATIONS_PREFIX.length))
  const updated = Object.fromEntries(await Promise.all(tools.map(async tool => [tool, await quietly(() => $.store.get(updatedKey(tool)))] as const)))
  // Dating and dropping lines is bookkeeping: without a clock the history still shows, all of it.
  const now = await quietly(() => $.clock.now())
  const { kept, stamp, gone } = now === undefined ? { kept: tools, stamp: [], gone: [] } : keptHistory(tools, updated, now)
  await Promise.all(stamp.map(tool => quietly(() => $.store.set(updatedKey(tool), now))))
  // The durations go first: should a later delete fail, nothing undated is left to be dated afresh.
  await Promise.all(gone.map(async tool => {
    await quietly(() => $.store.delete(historyKey(tool)))
    await Promise.all([updatedKey(tool), testsKey(tool)].map(key => quietly(() => $.store.delete(key))))
  }))
  return historyText(await Promise.all(kept.map(async tool => ({ tool, runs: (await $.store.get(historyKey(tool))) as number[] | undefined }))))
}
