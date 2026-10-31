/** The run the band shows: going while `ended` is absent, then its outcome until the band hides. */
export type BandRun = {
  tool: string
  /** `scheme on destination`, as far as it's known. */
  target?: string
  startedAt: number
  /** The tool's usual duration, from its earlier runs: what the band's gauge measures against. */
  usual?: number
  /** When the run itself began, which the gauge measures from: its start, or for a tool that logs, when the log appeared. */
  measuredFrom?: number
  /** What the run is doing now, read from its log: `compiling Utility · Formatter.swift`, `testing 312 of 959`. */
  phase?: string
  /** `hasFailures`: the run left failures, or the Mac's cause, in the pane, which the band points to. */
  /**
   * `isUnread`: the result said no outcome, as a call moved to the background answers. `background`: how the call's background
   * task ended, as its notification said.
   */
  ended?: { at: number; elapsed: number; ok: boolean; detail?: string; comparison?: string; hasFailures?: boolean; isUnread?: boolean; background?: { status?: string; durationMs?: number } }
}

/** A finished run as its row in the transcript draws it: its outcome, the first failures, and how many more. */
export type ResultRow = {
  ended: NonNullable<BandRun['ended']>
  failures: Pick<FailureList['items'][number], 'title' | 'where'>[]
  more: number
}

/** The last failing run's failures, for the failure pane. */
export type FailureList = {
  /** The run that failed: its tool, with the scheme and test selection when known. */
  tool: string
  /**
   * `isTest`: a failing test, which a later run can pass, rather than a compile error. `images`: the paths of the images it
   * attached, and `moreImages` how many more there are and where, as the CLI words it.
   */
  items: { title: string; message: string; where?: string; isTest?: boolean; images?: string[]; moreImages?: string; target?: string }[]
  /** Why the run failed when the cause is the Mac, with its fix, as `xcrew why` words it: the pane opens with it. */
  cause?: string
}

/** The runs going in the project's other worktrees, as `xcrew runs` last answered, and when. */
export type ElsewhereRun = { worktree: string; tool: string; phase?: string }
export type ElsewhereRuns = { runs: ElsewhereRun[]; at: number }

/** The most serious problem the band shows from `xcrew doctor`, and how many more there are. */
export type BandProblems = { isFailure: boolean; message: string; more: number; isRestart?: boolean }

/** The CLI build the shim named, and when it was asked: `path` is null when it named none. */
export type CliBuild = { path: string | null; at: number }

/** Manifest edits the project hasn't been generated since: one mark per app they changed, with the path the CLI gives the
 * app and the command that generates it, and whether a build was refused for them. */
export type StaleProject = { marks: { app: string; generate: string; files?: Record<string, string | null>; wasRefused?: true }[]; refused: boolean }

/** A full-suite run this session: when it ended, and how long it took. */
export type FullRun = { at: number; ms: number }

/** Each scope's recent full-suite runs this session, for the loop budget. */
export type FullRuns = Record<string, FullRun[]>

/** What `xcrew setup --choices` gives: the containers, the shared schemes with what each does, the installed simulators, the
 * starting picks, and the config there is. */
export type SetupChoices = {
  container?: string
  containers: string[]
  containerProblem?: string
  schemes: { name: string; container: string; roles: ('app' | 'unit-tests' | 'ui-tests')[]; app?: string }[]
  picks: { appScheme?: string; uiScheme?: string; testScheme?: string; bundleID?: string; testSimulator?: string; appSimulator?: string }
  simulators: { name: string; runtime: string; twoDisplays?: boolean }[]
  config?: { owner: 'xcrew' | 'edited' | 'other'; scheme?: string; debuggerBackend?: string }
  worktree?: boolean
}

/** What the person picked in the setup form, each passed to `xcrew setup` as its option. */
export type SetupPicks = SetupChoices['picks'] & { container?: string; debuggerBackend?: 'dap' | 'lldb-cli'; worktreeSimulator?: 'clone' | 'fresh' | 'share' }

/** The setup form: its choices once read, or why they couldn't be, the picks, and what the last write said. */
export type SetupForm = { choices: SetupChoices | null; picks: SetupPicks; unread?: string; isWriting?: boolean; written?: string[] }

declare module 'claude-code' {
  interface PluginState {
    xcrew: { run: BandRun | null; elsewhere: ElsewhereRuns | null; failures: FailureList | null; problems: BandProblems | null; build: CliBuild | null; row: StateFamily<ResultRow | null>; stale: StaleProject | null; loop: FullRuns; setup: boolean; form: SetupForm | null; wroteConfig: boolean }
  }
}
