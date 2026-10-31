import { atom, memberOf, read, update } from 'claude-code'
import type { EngineInterface, Register, RenderElement } from 'claude-code'
import type { BandProblems, BandRun, CliBuild, ElsewhereRuns, FailureList, FullRun, FullRuns, ResultRow, SetupChoices, SetupForm, SetupPicks, StaleProject } from '../../types'
import { changedRun, elsewhereTree, endedRun, outcomeLine, problemsTree, promptLine, resultTree, runTree, shownFor, showsRun } from './band'
import { afterRead, ELSEWHERE_EVERY_MS } from './elsewhere'
import { answerOf, couldntRun, generatedOf, type Head, hashOf, headOf, isGeneratedOf, knownBuild, manifestEditOf, namedBuild, notesOf, phaseArgs, profileSchemeOf, phaseOf, problemsOf, ranOutOfTime, reportArgs, reportOf, elsewhereOf, setupOfferOf, shimPath, xcodeHostsServerOf, xcodeSchemeOf, xcodeSelectionOf, type Failure, type Problem, type Ran, type Report } from './cli'
import { COMMAND, historyText, keptHistory, USAGE } from './command'
import { givesConcurrency, schemeOfScope } from './concurrency'
import { AFFECTED_TOOL, AFFECTED_TOOL_NAME, affectedArgs, affectedText } from './affected'
import { CARD_VERSION, cardText, type SavedCard } from './card'
import { currentProfile, describe, listingsSeen, profileKey, historyOf, isFullSuiteRun, isRepeatedRun, lost, namesScheme, observe, runsWholeScope, xcodeSelected, xcodeStarted } from './context'
import { EVIDENCE_TIMEOUT_MS, EVIDENCE_TOOL, EVIDENCE_TOOL_NAME, EVIDENCE_UNAVAILABLE, evidenceInput } from './evidence'
import { LOOK_TOOL, LOOK_TOOL_NAME, lookArgs } from './look'
import { afterTestRun, flakyText, label, type Ledger, LEDGER_PREFIX, LEDGER_TOOL, LEDGER_TOOL_NAME, LEDGER_UNAVAILABLE, ledgerKey, ledgerOf, ledgerText, staleLedgers, type TestRun } from './ledger'
import { afterRun, paneTree, summary } from './failures'
import { drawsForm, type FormElements, formTree, NO_FORM, PICK_KEYS, SETUP_FACT, setupArgs, startingPicks, WROTE } from './form'
import { afterFullRun, type Crossing, loopNote } from './loop'
import { average } from './format'
import { decided, describedForGenerated, editQuestion, editRefusal, type Question, XCODE_WRITE_QUESTION, xcodeWriteRefusal } from './guard'
import { mostSerious, noticed, REREAD_EVERY_MS, visible, WARNING_FOR_MS } from './problems'
import { afterGenerate, editedNote, isUndone, letThroughNote, marked, marksOf, refusal, refused, withoutUndone } from './regenerate'
import { DURATIONS_PREFIX, drawsBand, endingOf, FAILED_PREFIX, failedKey, type Following, historyKey, HISTORY, isStale, keyParts, labelOf, LONG_RUN_MS, logsKey, phaseStep, quietly, resultFor, SCOPE_PREFIXES, scopeKey, statusLine, testsKey, updatedKey, withContext } from './timing'
import { drawsRow, rowOf } from './rows'
import { buildsProject, FILE_EDITOR, forwardedTool, generatedPart, kindOf, mayBeGenerated, mayBeManifest, MCP_TOOL, parseTool, PROJECT_REWRITER, PROJECT_REWRITER_CALL, runsGenerate, runsSetup, type ToolKind } from './tools'

// The mod's state, which the loader reads only from atoms declared in the hooks module itself.
const runState = atom({ plugin: 'xcrew', key: 'run' } as const, null as BandRun | null)
const elsewhereState = atom({ plugin: 'xcrew', key: 'elsewhere' } as const, null as ElsewhereRuns | null)
const loopState = atom({ plugin: 'xcrew', key: 'loop' } as const, {} as FullRuns)
const failuresState = atom({ plugin: 'xcrew', key: 'failures' } as const, null as FailureList | null)
const problemsState = atom({ plugin: 'xcrew', key: 'problems' } as const, null as BandProblems | null)
/** The failures pane's id: a literal here, so the loader can read the pane hook's matcher. */
const FAILURES_PANE = 'xcrew-failures'
/** The shim's last answer, for the session: the build to run, or none. */
const buildState = atom({ plugin: 'xcrew', key: 'build' } as const, null as CliBuild | null)
/** Each run's outcome for its result row in the transcript, by the call's `tool_use_id`: the row's own `requestId`. */
const rowState = atom({ plugin: 'xcrew', key: 'row' } as const, null as ResultRow | null)
/** Whether this session has looked for a MobileBuildMCP profile with a build or test, after which it doesn't again. */
const setupState = atom({ plugin: 'xcrew', key: 'setup' } as const, false as boolean)
/** A manifest edit the project hasn't been generated since, for the session. */
const staleState = atom({ plugin: 'xcrew', key: 'stale' } as const, null as StaleProject | null)
/** The setup form's choices, picks and last write. */
const formState = atom({ plugin: 'xcrew', key: 'form' } as const, null as SetupForm | null)
/** The form wrote a config Claude hasn't been told of yet. */
const wroteConfigState = atom({ plugin: 'xcrew', key: 'wroteConfig' } as const, false as boolean)
/** The setup form's pane id: a literal here, so the loader can read the pane hook's matcher. */
const SETUP_PANE = 'xcrew-setup'

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
  on('tool.call', { tool: PROJECT_REWRITER_CALL }, async ($, e, next) => {
    const parsed = parseTool(e.tool)
    const target = parsed && (forwardedTool(parsed, e as unknown as Record<string, unknown>) ?? parsed)
    if (target?.tool !== 'XcodeWrite' || !(await isGeneratedProject($))) return next(e)
    const decision = decided(XCODE_WRITE_QUESTION, await ask($, XCODE_WRITE_QUESTION))
    return decision.allows ? next(e) : { deny: xcodeWriteRefusal(decision.said) }
  }).catch(async ($, e, next) => next(e))
  on('tool.describe', { tool: PROJECT_REWRITER }, async ($, e, next) => {
    const described = await next(e)
    return (await isGeneratedProject($)) ? { ...described, description: describedForGenerated(described.description) } : described
  })
  // After a manifest edit, the first call that builds the project is refused with the generate command; the next goes through.
  on('tool.call', { tool: MCP_TOOL }, async ($, e, next) => {
    const parsed = parseTool(e.tool)
    const target = parsed && (forwardedTool(parsed, e as unknown as Record<string, unknown>) ?? parsed)
    const stored = target && buildsProject(target) ? await quietly(() => read($, staleState)) : undefined
    // Edits undone since leave the manifests as the last generate read them: those marks go.
    const stale = stored && (await dropUndone($, stored))
    const generates = marksOf(stale).map(mark => mark.generate)
    if (!stale || generates.length === 0) return next(e)
    if (!stale.refused) {
      // Refused only once the mark says so: a refusal it can't record would repeat for good.
      if (await markStale($, refused)) return { deny: refusal(generates) }
      return next(e)
    }
    // An edit meanwhile left a mark not yet refused for, which stays.
    await markStale($, current => (current?.refused ? null : current))
    const result = await next(e)
    return result.deny === undefined ? withContext(result, letThroughNote(generates)) : result
  }).catch(async ($, e, next) => next(e))
  // The session's first MobileBuildMCP build or test says to offer setup while there's no scheme to build with. The mark
  // is set before the call, so calls started together ask once; the line is bookkeeping, so the call's result stands.
  on('tool.call', { tool: MCP_TOOL }, async ($, e, next) => {
    const parsed = parseTool(e.tool)
    if (parsed?.server !== 'MobileBuildMCP' || !buildsProject(parsed)) return next(e)
    let isFirst = false
    await quietly(() => update($, setupState, looked => ((isFirst = !looked), true)))
    if (!isFirst) return next(e)
    const result = await next(e)
    if (result.deny !== undefined) return result
    const offer = setupOfferOf(await answer($, ['project', '--profiles'], 10_000))
    return offer === undefined ? result : withContext(result, offer)
  }).catch(async ($, e, next) => next(e))
  on('tool.call', { tool: FILE_EDITOR }, async ($, e, next) => {
    const path = e.tool === 'Write' || e.tool === 'Edit' ? e.file_path : undefined
    // An edit to a file a generator writes waits for the person: the next generate would overwrite it.
    if (path !== undefined && mayBeGenerated(path)) {
      const generated = generatedOf(await answer($, ['project', '--generated', path], 10_000))
      if (generated) {
        const shown = generatedPart(path)
        const question = editQuestion(shown, generated)
        const decision = decided(question, await ask($, question))
        if (!decision.allows) return { deny: editRefusal(shown, generated, decision.said) }
      }
    }
    // What the file held before its first edit since the last generate, so an edit undone later can be told; read only
    // for a name a manifest may have.
    const isFirstEdit = path !== undefined && mayBeManifest(path) && !marksOf(await quietly(() => read($, staleState))).some(mark => path in (mark.files ?? {}))
    const before = isFirstEdit ? hashOf(await answer($, ['project', '--hash', path], 10_000)) : undefined
    const result = await next(e)
    if (path === undefined || result.deny !== undefined || result.isError || !mayBeManifest(path)) return result
    const edit = manifestEditOf(await answer($, ['project', '--manifest', path], 10_000))
    if (!edit) return result
    return (await markStale($, stale => marked(stale, edit, { path, before: before ?? null }))) ? withContext(result, editedNote(edit.generate)) : result
  }).catch(async ($, e, next) => next(e))
  on('tool.call', async ($, e, next) => {
    const parsed = parseTool(e.tool)
    if (!parsed) return next(e)
    const name = parsed.tool
    const kind = kindOf(parsed)
    if (!kind) {
      // Not timed, but its answer may say what the next build will use.
      const result = await next(e)
      const forwarded = forwardedTool(parsed, e as unknown as Record<string, unknown>)
      if (forwarded) lost(forwarded)
      else observe(parsed, result.text ?? '')
      // A call that failed may have a way around it, which the CLI names: an Xcode MCP call whose connection closed, or a
      // MobileBuildMCP error with another route. Not an Xcode MCP tool MobileBuildMCP proxies, through a bridge of its own
      // that reconnecting the plugin's server doesn't restart.
      if (parsed.proxied || result.isError !== true) return result
      const notes = notesOf(await answer($, ['note', '--server', parsed.server, '--error'], 10_000, result.text ?? ''))
      return notes.length > 0 ? withContext(result, ...notes) : result
    }
    const target = describe(parsed, e as unknown as Record<string, unknown>)
    const label = labelOf(name, target)
    const input = e as unknown as Record<string, unknown>
    // Durations and test totals are kept per repository, scheme and test selection, not only per tool. A MobileBuildMCP
    // call that names no scheme builds Xcode's selection, when Xcode hosts the server, or its profile's; one whose scheme
    // no one can name keeps no history.
    if (parsed.server === 'MobileBuildMCP' && input.scheme === undefined) await quietly(() => followXcode($))
    const needsScheme = parsed.server === 'MobileBuildMCP' && !namesScheme(parsed, input)
    const fallbackScheme = needsScheme ? await profileScheme($) : undefined
    const scope = historyOf(parsed, input, fallbackScheme)
    const key = needsScheme && fallbackScheme === undefined ? undefined : scopeKey(await sessionRoot($), scope)

    const started = await quietly(() => $.clock.now())
    const { passed: earlier, failed: earlierFailed } = await earlierRuns($, key, started)
    // What the gauge measures against; a tool's first run has none and shows its time alone.
    const usual = earlier.length > 0 ? average(earlier) : undefined
    const usesBand = drawsBand((await quietly(() => $.session.surfaces())) ?? [])
    // While this run goes, the other worktrees' runs are read too, so the line under it stays current.
    if (usesBand) void quietly(() => followElsewhere($))
    // MobileBuildMCP logs xcodebuild's output as the run goes; the Xcode MCP writes nothing to follow.
    const followsLog = parsed.server === 'MobileBuildMCP'
    const expectedTests = followsLog && key !== undefined ? ((await quietly(() => $.store.get(testsKey(key)))) as number | undefined) : undefined
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
    const repeated = kind === 'test' && isRepeatedRun(e as unknown as Record<string, unknown>)
    const reported = await answer($, reportArgs(parsed.server, kind, result.isError === true, repeated), 120_000, result.text ?? '')
    const outcome = withConcurrencyOnce(withPinNamedOnce(reportOf(reported, result.isError === true)), scope)
    // The server's own duration leaves out what ran around the call: a project's pre-build hook, a permission prompt.
    const elapsed = outcome.durationMs ?? ended - started
    // A result that says no outcome, as a call moved to the background answers, shows as neither and records nothing:
    // its real end comes later, as a task notification (`UserMessage` below).
    const run: Ending = { tool: name, scope, ...(key === undefined ? {} : { key }), earlierFailed, server: parsed.server, kind, earlier, usesBand, ranAll: runsWholeScope(parsed, input), fullSuite: isFullSuiteRun(parsed, input), ...(e.tool_use_id ? { toolUseId: e.tool_use_id } : {}) }
    if (outcome.isUnread && buildsProject(parsed)) {
      if (outcome.backgroundTask) {
        backgrounded.set(outcome.backgroundTask, { ...run, startedAt: started, repeated, ...(following.logPath === undefined ? {} : { log: following.logPath }) })
        // Kept until its notification's row is drawn; the oldest go first, so calls that never get one don't pile up.
        for (const old of [...backgrounded.keys()].slice(0, Math.max(0, backgrounded.size - UNREAD_KEPT))) backgrounded.delete(old)
      }
      await showEnding($, name, { at: ended, elapsed, ok: true, isUnread: true }, usesBand)
      return resultFor(result, outcome)
    }
    const loop = await recordEnding($, run, outcome, reported !== undefined, ended, elapsed)
    const resulting = resultFor(result, outcome)
    return loop ? withContext(resulting, loop) : resulting
  }).catch(async ($, e, next) => next(e))
  // A background task's notification carries the result of the call moved there: read as that call's, it ends the run
  // as a call answering in the foreground does, and Claude reads the shorter result with xcrew's notes. The call is
  // found by its task's id in the text; the CLI reads the rest. A result that can't be read leaves the run's log.
  on('prompt.submit', { origin: { kind: 'task-notification' } }, async ($, e, next) => {
    const task = [...backgrounded.keys()].find(id => !backgrounded.get(id)?.read && e.text.includes(id))
    const call = task === undefined ? undefined : backgrounded.get(task)
    if (task === undefined || !call) return next(e)
    const reading = readTask($, call, e.text)
    backgrounded.set(task, { ...call, read: reading.then(Boolean) })
    const read = await reading
    if (!read) return next(e)
    const context = [...(e.context ?? []), ...read.notes]
    return next({ ...e, ...(read.result === undefined ? {} : { text: read.result }), ...(context.length > 0 ? { context } : {}) })
  }).catch(async ($, e, next) => next(e))
  // The notification's row names its task: one whose result wasn't read gets its line, just after the drawing, which
  // changes nothing itself.
  on('ui.render', { component: 'UserMessage', props: { origin: { kind: 'task-notification' } } }, async ($, e, next) => {
    const task = (e.props as { task?: { id?: string; status?: string; durationMs?: number } }).task
    const call = task?.id === undefined ? undefined : backgrounded.get(task.id)
    // A row drawn before its notification is read leaves the call to the reading; a later drawing says what it found.
    if (task?.id !== undefined && call?.read) {
      backgrounded.delete(task.id)
      void quietly(() =>
        $.clock.after(0, async () => {
          if (await call?.read) return
          const now = await quietly(() => $.clock.now())
          if (now === undefined) return
          const usesBand = drawsBand((await quietly(() => $.session.surfaces())) ?? [])
          // A run going meanwhile keeps the band: the notification is an earlier call's.
          if (usesBand && (await anotherRunGoing($))) return
          await showEnding($, call.tool, { at: now, elapsed: task.durationMs ?? 0, ok: true, background: { ...(task.status ? { status: task.status } : {}), ...(task.durationMs === undefined ? {} : { durationMs: task.durationMs }) } }, usesBand)
        }),
      )
    }
    return next(e)
  })
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const elements = $.ui.resolve(e)
    const elsewhere = await quietly(() => read($, elsewhereState))
    // The other worktrees' runs go on a line of their own, below whatever the band shows first.
    const withElsewhere = (first: RenderElement): RenderElement =>
      elsewhere ? elements.Box({ flexDirection: 'column', children: [first, elsewhereTree(elements, elsewhere.runs)] }) : first
    const run = await read($, runState)
    const now = await $.clock.now()
    // A run going has the band; then the restart, which fixes most of what a finished run or a problem shows.
    if (run && !run.ended) return withElsewhere(runTree(elements, run, now))
    const problems = await read($, problemsState)
    if (problems?.isRestart) return withElsewhere(problemsTree(elements, problems))
    if (showsRun(run, now)) return withElsewhere(runTree(elements, run, now))
    if (problems) return withElsewhere(problemsTree(elements, problems))
    return elsewhere ? elsewhereTree(elements, elsewhere.runs) : next(e)
  })
  // A run's row in the transcript draws its outcome while the surface says it's collapsed; expanded (ctrl+o), or where the
  // surface doesn't say, it's the result Claude read, which is untouched.
  on('ui.render', { component: 'ToolResult', props: { tool: MCP_TOOL } }, async ($, e, next) => {
    const parsed = parseTool(e.props.tool)
    // Only a build or a test run has a row, so no other call's drawing reads state.
    if (e.props.isExpanded !== false || !parsed || !drawsRow(kindOf(parsed))) return next(e)
    const row = await read($, memberOf(rowState, e))
    return row ? resultTree($.ui.resolve(e), parsed.tool, row) : next(e)
  })
  // Claude's question before a full test run: which tests the branch's changes can break.
  // The time `/xcrew doctor` gets: the first call after an update builds the CLI.
  on('tool.call', { tool: AFFECTED_TOOL_NAME }, async ($, e) => ({ result: affectedText(await answer($, affectedArgs(e as unknown as Record<string, unknown>), 120_000)) }))
  // Claude's read of the ledger, for a pull request's test plan.
  on('tool.call', { tool: LEDGER_TOOL_NAME }, async $ => ({ result: await ledgerNow($) }))
  // Claude's look at a failed UI test: the steps before the failure and the screen at it.
  on('tool.call', { tool: LOOK_TOOL_NAME }, async ($, e) => ({ result: await cliText($, lookArgs(e as unknown as Record<string, unknown>)) }))
  // Claude's evidence for a pull request's body.
  on('tool.call', { tool: EVIDENCE_TOOL_NAME }, async $ => ({ result: await evidenceNow($) }))
  on('command.run', { command: 'xcrew' }, async ($, e) => {
    const subcommand = (e.args ?? '').trim()
    if (subcommand === 'doctor') return { text: await cliText($, ['doctor']) }
    if (subcommand === 'xcode') return { text: await cliText($, ['xcode']) }
    if (subcommand === 'history') return { text: await history($) }
    if (subcommand === 'ledger') return { text: await ledgerNow($) }
    if (subcommand === 'flaky') return { text: await ledgerNow($, flakyText) }
    if (subcommand === 'evidence') return { text: await evidenceNow($) }
    if (subcommand === 'failures') {
      await dismissFailedRun($)
      return { text: await openFailures($) }
    }
    if (subcommand === 'setup') return { text: await openForm($) }
    if (subcommand === 'close') {
      await dismissFailedRun($)
      return { text: await closeFailures($) }
    }
    return { text: USAGE }
  }).catch(async ($, e, next) => ({ text: `/xcrew ${(e.args ?? '').trim()} couldn't answer: ${next.error?.message ?? 'it failed'}` }))
  on('ui.render', { component: 'Pane', requestId: FAILURES_PANE }, async ($, e) => paneTree($.ui.resolve(e), await read($, failuresState)))
  on('ui.render', { component: 'Pane', requestId: SETUP_PANE }, async ($, e) => formTree($.ui.resolve(e) as unknown as FormElements, await read($, formState), {
    pick: (key, value) => void pickInForm($, key, value).catch(() => undefined),
    write: () => void writeFromForm($).catch(() => undefined),
    close: () => void $.ui.close({ id: SETUP_PANE }).catch(() => undefined),
  }))
  // The one unmatched session start hook: offers `/xcrew`, and looks for problems without holding the session up.
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await $.command.register(COMMAND)
    for (const tool of [LEDGER_TOOL, AFFECTED_TOOL, LOOK_TOOL, EVIDENCE_TOOL]) await quietly(() => $.tool.register(tool))
    // A cleared conversation is a new session: its warnings show again, and the pin is named again.
    sessionRootRead = undefined
    sessionProfileSchemes = new Map()
    found = []
    pinsNamed.clear()
    concurrencyGiven.clear()
    seenAt = {}
    void loadProblems($).catch(() => undefined)
    void quietly(() => readXcodeStart($))
    // The card is saved from the history as it's left: fresh, and this version's.
    void quietly(() => pruneHistory($)).then(() => saveCard($))
    return started
  })
  // The one unmatched prompt hook: a problem fixed any way at all leaves the band by the next prompt. Never awaited.
  on('prompt.submit', async ($, e, next) => {
    // A config the form wrote is told once: the session's MobileBuildMCP still runs on the old one. A read first, so
    // a prompt writes nothing when there's nothing to tell.
    if ((await quietly(() => read($, wroteConfigState))) === true) {
      await quietly(() => update($, wroteConfigState, () => false))
      e = withContext(e, SETUP_FACT)
    }
    void (async () => {
      if (!drawsBand((await quietly(() => $.session.surfaces())) ?? [])) return
      void quietly(() => followElsewhere($))
      if ((await $.clock.now()) - lastRead >= REREAD_EVERY_MS) await loadProblems($)
    })().catch(() => undefined)
    return next(e)
  })
  // Setup may have written the config: look at once whether MobileBuildMCP now needs a restart. A generate that finished
  // brings the project up to its manifests.
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const result = await next(e)
    if (e.tool !== 'Bash') return result
    if (runsSetup(e.command)) afterSetup($)
    if (runsGenerate(e.command) && !e.run_in_background && result.deny === undefined && !result.isError) await markStale($, stale => afterGenerate(stale, e.command))
    return result
  }).catch(async ($, e, next) => next(e))
}

/** A finished build, test or run call, as its ending is recorded. */
type Ending = { tool: string; scope: string; key?: string; earlierFailed: readonly number[]; server: string; kind: ToolKind; earlier: readonly number[]; usesBand: boolean; ranAll: boolean; fullSuite: boolean; toolUseId?: string }

/** A call moved to the background, as its notification's reading needs it: once read, whether its result was. */
type Backgrounded = Ending & { startedAt: number; repeated: boolean; log?: string; read?: Promise<boolean> }

/**
 * Records how a run ended: its time in the history, apart when it failed, its failures, the ledger when the CLI read the run (`isRead`) and
 * read more than a log's verdict, the card, its row and the band; the loop note, when a full run crossed the budget.
 */
async function recordEnding($: EngineInterface, run: Ending, outcome: Report, isRead: boolean, ended: number, elapsed: number): Promise<string | undefined> {
  const { tool, scope, key, kind, earlier, earlierFailed } = run
  if (key !== undefined) {
    // A failed run's time is kept apart: one that fails early would pull the usual time down. Both lists are written as
    // read when the run began, so a scope gone stale starts over whichever way the run ended.
    const add = (runs: readonly number[]) => [...runs, elapsed].slice(-HISTORY)
    await quietly(() => $.store.set(historyKey(key), outcome.ok ? add(earlier) : [...earlier]))
    await quietly(() => $.store.set(failedKey(key), outcome.ok ? [...earlierFailed] : add(earlierFailed)))
    await quietly(() => $.store.set(updatedKey(key), ended))
  }
  await quietly(() => recordRun($, scope, outcome.ok, outcome.failures, outcome.cause))
  // Only what the CLI read goes in the ledger: without it, or from a log's verdict alone, the outcome says no test's own.
  const readTests = kind === 'test' && isRead && !outcome.isVerdictOnly
  if (readTests) recordLedger($, { scope, at: ended, ok: outcome.ok, failures: outcome.failures, ranAll: run.ranAll, repeated: outcome.repeated ?? [], bundle: outcome.bundle })
  // A failed run may have stopped early: its count is no total for the next run's.
  if (key !== undefined && outcome.ok && outcome.tests !== undefined) await quietly(() => $.store.set(testsKey(key), outcome.tests))
  saveCard($)
  const ending = endingOf(outcome, ended, elapsed, earlier)
  const requestId = run.toolUseId
  if (drawsRow(kind) && requestId) await quietly(() => update($, memberOf(rowState, { requestId }), () => rowOf(ending, outcome.failures)))
  await showEnding($, tool, ending, run.usesBand)
  // Long enough that the person has likely looked away; their notification settings decide how it arrives.
  if (elapsed >= LONG_RUN_MS) await quietly(() => $.ui.notify(outcomeLine(tool, ending)))
  // A whole suite run again and again: past the budget, the tests the change can break would do.
  // Only a run the CLI read and that ran tests counts: a test build that failed ran none.
  const ranTests = outcome.tests === undefined ? outcome.ok || outcome.failures.some(failure => failure.isTest) : outcome.tests > 0
  const loop = readTests && ranTests && run.fullSuite ? await quietly(() => countFullRun($, scope, { at: ended, ms: elapsed })) : undefined
  return loop ? loopNote(scope, loop, run.server === 'MobileBuildMCP') : undefined
}

/**
 * Reads a backgrounded call's notification for its result, or the run's log when that has none to read, and records
 * how the run ended, from the call to the notification. Nothing, when neither says.
 */
async function readTask($: EngineInterface, call: Backgrounded, text: string): Promise<{ result?: string; notes: string[] } | undefined> {
  const args = [...reportArgs(call.server, call.kind, false, call.repeated), '--notification', ...(call.log === undefined ? [] : ['--log', call.log])]
  const reported = await answer($, args, 120_000, text)
  const outcome = withPinNamedOnce(reportOf(reported, false))
  if (reported === undefined || outcome.isUnread) return undefined
  const ended = await quietly(() => $.clock.now())
  if (ended === undefined) return undefined
  // A run going meanwhile keeps the band: this one ended earlier, in the background.
  const usesBand = call.usesBand && !(await anotherRunGoing($))
  // The runs that ended meanwhile count among the earlier ones; the server's time leaves out the wait for the notification.
  const { passed: earlier, failed: earlierFailed } = await earlierRuns($, call.key, ended)
  const loop = await recordEnding($, { ...call, usesBand, earlier }, outcome, true, ended, outcome.durationMs ?? ended - call.startedAt)
  // Given only once it reaches Claude: a note dropped above isn't counted as read.
  const notes = withConcurrencyOnce(outcome, call.scope).notes
  return { ...(outcome.result === undefined ? {} : { result: outcome.result }), notes: [...notes, ...(loop ? [loop] : [])] }
}

/** Whether a run is going now: it keeps the band from a call that ended in the background meanwhile. */
async function anotherRunGoing($: EngineInterface): Promise<boolean> {
  const going = await quietly(() => read($, runState))
  return going !== undefined && going !== null && !going.ended
}

/** The stale project without the marks whose edits are undone, each edited file back to its hash from before. */
async function dropUndone($: EngineInterface, stale: StaleProject): Promise<StaleProject | null> {
  const files = [...new Set(marksOf(stale).flatMap(mark => Object.keys(mark.files ?? {})))]
  if (files.length === 0) return stale
  const now = Object.fromEntries(await Promise.all(files.map(async file => [file, hashOf(await answer($, ['project', '--hash', file], 10_000))] as const)))
  const undone = marksOf(stale).filter(mark => isUndone(mark, now))
  if (undone.length === 0) return stale
  let left: StaleProject | null = stale
  await quietly(() => update($, staleState, current => (left = withoutUndone(current, undone))))
  return left
}

/** Changes the marks of a stale project; false when the state couldn't be written. */
function markStale($: EngineInterface, change: (stale: StaleProject | null) => StaleProject | null): Promise<boolean> {
  return quietly(() => update($, staleState, change).then(() => true)).then(Boolean)
}

/** The person's answer to `question`, or nothing when there's nobody to ask: a run without a person, or a dismissed dialog. */
function ask($: EngineInterface, question: Question): Promise<string | undefined> {
  return quietly(() => $.ui.ask(question.question, { options: [...question.options], header: question.header }))
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

/**
 * Shows how a run ended: on the band where one draws, the run going there ending with it, for as long as an ending
 * stays; elsewhere a toast carries the same line.
 */
async function showEnding($: EngineInterface, tool: string, ending: NonNullable<BandRun['ended']>, usesBand: boolean): Promise<void> {
  if (!usesBand) return void (await quietly(() => $.ui.toast(promptLine(tool, ending))))
  await quietly(() => update($, runState, run => (run && !run.ended ? endedRun(run, ending) : { tool, startedAt: ending.at, ended: ending })))
  // The outcome leaves the band on its own; a later run has replaced it by then, or it's this one.
  await quietly(() => $.clock.after(shownFor(ending) + 1, () => void quietly(() => update($, runState, run => (run?.ended?.at === ending.at ? null : run)))))
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

/** A CLI command's own text, or why it couldn't run. */
function cliText($: EngineInterface, args: string[]): Promise<string> {
  return xcrew($, args, 120_000).then(ran => `${ran.stdout}${ran.stderr}`.trimEnd(), error => couldntRun(args, error))
}

/** Opens the setup form and reads its choices behind it; where nothing draws pickers, names the skill. */
async function openForm($: EngineInterface): Promise<string> {
  if (!drawsForm((await quietly(() => $.session.surfaces())) ?? [])) return NO_FORM
  await update($, formState, () => ({ choices: null, picks: {} }))
  const opened = await $.ui.open({ id: SETUP_PANE, title: 'xcrew setup' })
  if (!opened.isPlaced) return `The setup form couldn't be placed${'reason' in opened && opened.reason ? `: ${opened.reason}` : ''}. /xcrew:setup, the skill, sets xcrew up from here.`
  // The pane says it's reading meanwhile; the command's own line waits for the choices.
  await readChoices($).catch(() => undefined)
  return 'The setup form is open in a pane: pick, then Write config.'
}

/** Reads what setup offers, for `container` when the person picked one, and starts the picks from it. */
async function readChoices($: EngineInterface, container?: string, written?: string[]): Promise<void> {
  const answered = await answer($, ['setup', '--choices', ...(container ? ['--container', container] : [])], 120_000)
  const choices = answered !== null && typeof answered === 'object' && Array.isArray((answered as SetupChoices).containers) ? (answered as SetupChoices) : undefined
  await update($, formState, form => (choices
    ? { choices, picks: { ...startingPicks(choices), ...(container ? { container } : {}) }, ...(written ? { written } : {}) }
    : { choices: null, picks: form?.picks ?? {}, unread: 'xcrew setup --choices couldn\'t answer: /xcrew:setup, the skill, sets xcrew up instead.' }))
}

async function pickInForm($: EngineInterface, key: string, value: string): Promise<void> {
  if (key === 'container') {
    await update($, formState, form => ({ choices: null, picks: { ...(form?.picks ?? {}), container: value } }))
    return readChoices($, value)
  }
  const pick = PICK_KEYS[key]
  if (!pick) return
  await update($, formState, form => (form ? { ...form, picks: { ...form.picks, [pick]: value === '' ? undefined : value } as SetupPicks } : form))
}

/** Runs `xcrew setup` with the picks, shows what it said, and has Claude told once when it wrote the config. */
async function writeFromForm($: EngineInterface): Promise<void> {
  // Taken in one update, so a second press while the first writes finds it taken.
  let form: SetupForm | null = null
  await update($, formState, current => {
    if (!current?.choices || current.isWriting) return current
    form = current
    return { ...current, isWriting: true, written: undefined }
  })
  const taken = form as SetupForm | null
  if (!taken?.choices) return
  const said = await cliText($, setupArgs(taken.choices, taken.picks))
  const written = said.split('\n').filter(line => line.trim() !== '')
  await update($, formState, current => (current ? { ...current, isWriting: false, written } : current))
  if (said.includes(WROTE)) {
    await quietly(() => update($, wroteConfigState, () => true))
    afterSetup($)
    // The config is xcrew's now: the form says so, and a second write needs no --force.
    await readChoices($, taken.picks.container, written).catch(() => undefined)
  }
}

/** Setup may have written the profiles: their scheme is read again, and whether MobileBuildMCP needs a restart. */
function afterSetup($: EngineInterface): void {
  sessionProfileSchemes = new Map()
  void loadProblems($, true).catch(() => undefined)
}

/** A run has the band while it shows; the problems wait beneath it. */
function startRun($: EngineInterface, run: BandRun): Promise<unknown> {
  return update($, runState, () => run)
}

/**
 * Saves the project card for this folder and branch, for the session-start hook to print: Claude Code passes over a
 * plugin's prompt hooks on some plans, so the card can't ride on a prompt. After the ledger's own writes; best-effort,
 * never awaited, and saved one at a time.
 */
function saveCard($: EngineInterface): void {
  cardWrites = cardWrites
    .then(() =>
      // A save the CLI never answers gives way, so the next one still lands.
      Promise.race([
        (async () => {
          const card = await cardNow($)
          const saved = card && JSON.stringify(card)
          if (!saved || saved === lastSavedCard) return
          await answer($, ['card', '--save'], 10_000, saved)
          lastSavedCard = saved
        })(),
        $.clock.sleep(CARD_SAVE_MS),
      ]),
    )
    .catch(() => undefined)
}

/**
 * What the mod knows of this folder and branch: the run scopes of this repository, still fresh, and the branch's
 * ledger as `/xcrew ledger` shows it, read once the ledger's pending writes have landed. The card and the evidence read
 * the same.
 */
async function branchState($: EngineInterface) {
  await ledgerWrites
  const [folder, now] = await Promise.all([$.session.cwd(), $.clock.now()])
  const root = await sessionRoot($)
  const scopes = (await storedHistory($)).filter(entry => entry.root === root && !isStale(entry.updated, now))
  const { head, ledger } = await branchLedger($)
  return { folder, now, head, scopes, entries: ledger?.entries ?? [], updated: ledger?.updated }
}

/** The card as the CLI keeps it: its folder and branch, the time of its newest data, and its text, if it has any. */
async function cardNow($: EngineInterface): Promise<SavedCard | undefined> {
  const { folder, now, head, scopes, entries, updated: ledgerUpdated } = await branchState($)
  if (!head) return undefined
  // The card is read at every session start, so it drops what no run has written for as long as the history is kept.
  const red = isStale(ledgerUpdated, now) ? [] : entries.filter(entry => !entry.green && !isStale(entry.last, now))
  const text = cardText(scopes, red, label(head, true))
  const times = [...scopes.map(entry => entry.updated), ...red.map(entry => entry.last)].filter((time): time is number => typeof time === 'number')
  const [updated, oldest] = times.length > 0 ? [Math.max(...times), Math.min(...times)] : [now, now]
  return { version: CARD_VERSION, folder, branch: label(head, false), updated, oldest, ...(text ? { text } : {}) }
}

/** The evidence for this branch, as the CLI words it from the ledger and the run times of the scopes last run in this folder. */
async function evidenceNow($: EngineInterface): Promise<string> {
  const { head, entries, scopes } = await branchState($)
  if (!head) return EVIDENCE_UNAVAILABLE
  // Its stdout alone: the block is pasted into a pull request as it is, and stderr is the shim's and the tools' own.
  return xcrew($, ['evidence'], EVIDENCE_TIMEOUT_MS, evidenceInput(entries, scopes)).then(ran => ran.stdout.trimEnd(), error => couldntRun(['evidence'], error))
}

/**
 * Every run scope the store holds under this version's keys, with its root, its passing and failed runs' durations, when
 * a run last updated it, and its test total.
 */
async function storedHistory($: EngineInterface): Promise<{ key: string; root: string; scope: string; runs: number[]; failed: number[]; updated: unknown; tests?: number }[]> {
  const stored = await $.store.keys()
  const keys = [...new Set([DURATIONS_PREFIX, FAILED_PREFIX].flatMap(prefix => stored.filter(key => key.startsWith(prefix)).map(key => key.slice(prefix.length))))]
  const scoped = keys.flatMap(key => {
    const parts = keyParts(key)
    return parts ? [{ key, ...parts }] : []
  })
  return Promise.all(scoped.map(async ({ key, root, scope }) => {
    const [runs, failed, updated, tests] = await Promise.all([historyKey, failedKey, updatedKey, testsKey].map(name => quietly(() => $.store.get(name(key)))))
    return { key, root, scope, runs: Array.isArray(runs) ? (runs as number[]) : [], failed: Array.isArray(failed) ? (failed as number[]) : [], updated, ...(typeof tests === 'number' ? { tests } : {}) }
  }))
}

/**
 * The root of this session's repository, as `xcrew project --branch` names it, else the session's folder: kept once
 * read, so a read the CLI never answers holds up only its own caller.
 */
let sessionRootRead: string | undefined

async function sessionRoot($: EngineInterface): Promise<string> {
  if (sessionRootRead !== undefined) return sessionRootRead
  const named = headOf(await answer($, ['project', '--branch'], 10_000))?.root
  // Only a root the CLI named is kept: one it couldn't name yet, as while it builds, is asked for again.
  if (named !== undefined) sessionRootRead = named
  return named ?? (await quietly(() => $.session.cwd())) ?? ''
}

/** Whether a timer reads the other worktrees' runs: set before any wait, so callers at once start one. */
let followingElsewhere = false

/**
 * The scheme each MobileBuildMCP profile builds with, for a call that names none, once the CLI has answered: the config's
 * active one under `''`. Read again after setup.
 */
let sessionProfileSchemes = new Map<string, { scheme?: string }>()

async function profileScheme($: EngineInterface): Promise<string | undefined> {
  const profile = currentProfile()
  const cached = sessionProfileSchemes.get(profileKey())
  if (cached) return cached.scheme
  const answered = await answer($, ['project', '--profiles', ...(profile === undefined ? [] : ['--profile', profile])], 10_000)
  if (answered === undefined) return undefined
  const scheme = profileSchemeOf(answered)
  sessionProfileSchemes.set(profileKey(), scheme === undefined ? {} : { scheme })
  return scheme
}

/**
 * Where MobileBuildMCP reads Xcode's selection and whether it follows it, once the CLI has answered; null when Xcode
 * doesn't host the server. Kept across a cleared conversation, as the server is.
 */
let xcodeSelection: Promise<{ state: string; follows: boolean } | null | undefined> | undefined

/** Reads the selection at the server's start once: a CLI that couldn't answer, or found no server yet, is asked again. */
async function readXcodeStart($: EngineInterface): Promise<{ state: string; follows: boolean } | null | undefined> {
  const listings = listingsSeen()
  xcodeSelection ??= answer($, ['project', '--xcode'], 10_000).then(answered => {
    if (xcodeHostsServerOf(answered) === undefined) return undefined
    const read = xcodeSelectionOf(answered)
    if (read) xcodeStarted(read.scheme, read.activeProfile, listings)
    return read ? { state: read.state, follows: read.follows } : null
  })
  const read = await xcodeSelection
  if (read === undefined) xcodeSelection = undefined
  return read
}

/** Before a MobileBuildMCP run, takes a selection Xcode changed since, while the server follows it. */
async function followXcode($: EngineInterface): Promise<void> {
  const read = await readXcodeStart($)
  if (!read?.follows) return
  xcodeSelected(xcodeSchemeOf(await answer($, ['project', '--xcuserstate', read.state], 10_000)))
}

/** A scope's passing and failed runs before this one, read when it began: none once no run has updated it for weeks. */
async function earlierRuns($: EngineInterface, key: string | undefined, now: number | undefined): Promise<{ passed: number[]; failed: number[] }> {
  if (key === undefined) return { passed: [], failed: [] }
  const [passed, failed, updated] = await Promise.all([historyKey, failedKey, updatedKey].map(name => quietly(() => $.store.get(name(key)))))
  // Runs from weeks ago say nothing about this one: they don't count, and this run starts the line afresh.
  if (now !== undefined && isStale(updated, now)) return { passed: [], failed: [] }
  return { passed: Array.isArray(passed) ? (passed as number[]) : [], failed: Array.isArray(failed) ? (failed as number[]) : [] }
}

/** Drops a scope's keys, its durations first: should a later delete fail, nothing is left to count or to be dated afresh. */
async function dropScope($: EngineInterface, key: string): Promise<void> {
  await quietly(() => $.store.delete(historyKey(key)))
  await Promise.all(SCOPE_PREFIXES.filter(prefix => prefix !== DURATIONS_PREFIX).map(prefix => quietly(() => $.store.delete(`${prefix}${key}`))))
}

/**
 * Leaves the history with this version's keys, each holding runs a run wrote lately: a scope stored before keys held
 * their root, one no run has updated for as long as the history is kept, and one with no runs, all go.
 */
async function pruneHistory($: EngineInterface): Promise<void> {
  const [keys, now] = await Promise.all([$.store.keys(), $.clock.now()])
  const scopes = new Set<string>()
  for (const stored of keys) {
    const prefix = SCOPE_PREFIXES.find(candidate => stored.startsWith(candidate))
    if (prefix) scopes.add(stored.slice(prefix.length))
  }
  await Promise.all([...scopes].map(async key => {
    const [runs, failed, updated] = await Promise.all([historyKey(key), failedKey(key), updatedKey(key)].map(name => $.store.get(name)))
    const isEmpty = (!Array.isArray(runs) || runs.length === 0) && (!Array.isArray(failed) || failed.length === 0)
    if (keyParts(key) && !isEmpty && !isStale(updated, now)) return
    await dropScope($, key)
  }))
}

/** Counts a full-suite run toward the loop budget: the runs that crossed it, when this one did. */
async function countFullRun($: EngineInterface, scope: string, run: FullRun) {
  let crossed: Crossing | undefined
  await update($, loopState, runs => {
    const after = afterFullRun(runs[scope] ?? [], run)
    crossed = after.crossed
    return { ...runs, [scope]: after.runs }
  })
  return crossed
}

/** The checkout the CLI names, and its ledger. */
async function branchLedger($: EngineInterface): Promise<{ head?: Head; ledger?: Ledger }> {
  const head = headOf(await answer($, ['project', '--branch'], 10_000))
  if (!head) return {}
  const ledger = ledgerOf(await $.store.get(ledgerKey(head)))
  return { head, ...(ledger ? { ledger } : {}) }
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

async function recordRun($: EngineInterface, run: string, ok: boolean, items: Failure[], cause?: string): Promise<void> {
  const list = await read($, failuresState)
  const after = afterRun(list, run, ok, items, cause)
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

/** The card's saves, one after another, so a later one never lands before an earlier. */
let cardWrites: Promise<unknown> = Promise.resolve()
/** The card last saved, so one that hasn't changed isn't saved again. */
let lastSavedCard: string | undefined
/** How long one save may take before the next goes ahead. */
const CARD_SAVE_MS = 15_000
/** The calls moved to the background, by the task their handle named, until its notification's row is drawn. */
const backgrounded = new Map<string, Backgrounded>()
/** How many calls are kept waiting for their notification. */
const UNREAD_KEPT = 20

/** The highest concurrency count Claude has read this session, by scheme. */
const concurrencyGiven = new Map<string, number>()

/** Adds the run's concurrency note the first time its scheme has one this session, and when its count rises far enough
 * above the highest given: a build and a test run of one scheme, whatever their selections, build the same code. */
function withConcurrencyOnce(outcome: Report, scope: string): Report {
  const counted = outcome.concurrency
  const scheme = schemeOfScope(scope)
  if (!counted || !givesConcurrency(concurrencyGiven.get(scheme), counted.count)) return outcome
  concurrencyGiven.set(scheme, counted.count)
  return { ...outcome, notes: [...outcome.notes, counted.note] }
}

/** The pins Claude has read of this session: each is named with the first failure it may explain, and not again. */
const pinsNamed = new Set<string>()

function withPinNamedOnce(outcome: Report): Report {
  const pin = outcome.pin ?? outcome.pinNote
  if (!outcome.pinNote || !pin || pinsNamed.has(pin)) return outcome
  pinsNamed.add(pin)
  return { ...outcome, notes: [...outcome.notes, outcome.pinNote] }
}
/** The ledger writes in flight, one after another, so two runs ending together each keep their entries. */
let ledgerWrites: Promise<unknown> = Promise.resolve()

/** Writes a finished test run into its branch's ledger, after the writes before it, without holding up the run's result. */
function recordLedger($: EngineInterface, run: TestRun): void {
  ledgerWrites = ledgerWrites.then(() => writeLedger($, run)).catch(() => undefined)
}

/** Writes a run into its branch's ledger, and drops the ledgers no run has written for as long as the history is kept. */
async function writeLedger($: EngineInterface, run: TestRun): Promise<void> {
  const head = headOf(await answer($, ['project', '--branch'], 10_000))
  if (!head) return
  const key = ledgerKey(head)
  await $.store.set(key, afterTestRun(ledgerOf(await $.store.get(key)), run))
  const others = (await $.store.keys()).filter(stored => stored.startsWith(LEDGER_PREFIX) && stored !== key)
  const stored = Object.fromEntries(await Promise.all(others.map(async other => [other, await $.store.get(other)] as const)))
  await Promise.all(staleLedgers(stored, run.at).map(stale => quietly(() => $.store.delete(stale))))
}

/** Reads the other worktrees' runs into the line: what the CLI answers, or what it held, until that ages out. */
async function readElsewhere($: EngineInterface): Promise<void> {
  const read = elsewhereOf(await answer($, ['runs'], 10_000))
  const now = await quietly(() => $.clock.now())
  if (now === undefined) return
  await quietly(() => update($, elsewhereState, held => afterRead(held, read, now)))
  await quietly(() => $.ui.invalidate('ui.render'))
}

/** Reads the other worktrees' runs now, then every few seconds until none shows and no run of this session's goes. */
async function followElsewhere($: EngineInterface): Promise<void> {
  // Taken before any wait, so callers at once start one timer.
  if (followingElsewhere) return readElsewhere($)
  followingElsewhere = true
  await readElsewhere($)
  let reading = false
  const timer = await quietly(() =>
    $.clock.every(ELSEWHERE_EVERY_MS, async () => {
      // A read that outlasts the period isn't joined by another.
      if (reading) return
      reading = true
      try {
        await readElsewhere($)
        const [shown, run] = await Promise.all([quietly(() => read($, elsewhereState)), quietly(() => read($, runState))])
        if (shown || (run && !run.ended)) return
        timer?.cancel()
        followingElsewhere = false
      } finally {
        reading = false
      }
    }),
  )
  if (!timer) followingElsewhere = false
}

/** The ledger of the branch checked out now, after the writes of a run that just ended, as `text` words it. */
async function ledgerNow($: EngineInterface, text: (ledger: Ledger | undefined, head: Head) => string = ledgerText): Promise<string> {
  await ledgerWrites
  const { head, ledger } = await branchLedger($)
  return head ? text(ledger, head) : LEDGER_UNAVAILABLE
}

/** `/xcrew history`: this repository's scopes, those a run updated within the history's time; an undated one is dated now. */
async function history($: EngineInterface): Promise<string> {
  const root = await sessionRoot($)
  const stored = (await storedHistory($)).filter(entry => entry.root === root)
  const keys = stored.map(entry => entry.key)
  const updated = Object.fromEntries(stored.map(entry => [entry.key, entry.updated]))
  // Dating and dropping lines is bookkeeping: without a clock the history still shows, all of it.
  const now = await quietly(() => $.clock.now())
  const { kept, stamp, gone } = now === undefined ? { kept: keys, stamp: [], gone: [] } : keptHistory(keys, updated, now)
  await Promise.all(stamp.map(key => quietly(() => $.store.set(updatedKey(key), now))))
  await Promise.all(gone.map(key => dropScope($, key)))
  const byKey = new Map(stored.map(entry => [entry.key, entry]))
  return historyText(kept.flatMap(key => {
    const entry = byKey.get(key)
    return entry ? [{ tool: entry.scope, runs: entry.runs, failed: entry.failed }] : []
  }))
}
