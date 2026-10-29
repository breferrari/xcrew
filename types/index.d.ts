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
  /** `hasFailures`: the run left failures in the pane, which the band points to. */
  ended?: { at: number; elapsed: number; ok: boolean; detail?: string; comparison?: string; hasFailures?: boolean }
}

/** The last failing run's failures, for the failure pane. */
export type FailureList = {
  /** The run that failed: its tool, with the scheme and test selection when known. */
  tool: string
  items: { title: string; message: string; where?: string }[]
}

/** The most serious problem `xcrew doctor` found at session start, and how many more there are. */
export type BandProblems = { isFailure: boolean; message: string; more: number }

/** The CLI build the shim named, and when it was asked: `path` is null when it named none. */
export type CliBuild = { path: string | null; at: number }

declare module 'claude-code' {
  interface PluginState {
    xcrew: { run: BandRun | null; failures: FailureList | null; problems: BandProblems | null; build: CliBuild | null }
  }
}
