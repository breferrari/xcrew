/** The run the band shows: going while `ended` is absent, then its outcome until the band hides. */
export type BandRun = {
  tool: string
  /** `scheme on destination`, as far as it's known. */
  target?: string
  startedAt: number
  /** The tool's usual duration, from its earlier runs: what the band's gauge measures against. */
  usual?: number
  /** What the run is doing now, read from its log: `compiling Utility · Formatter.swift`, `testing 312 of 959`. */
  phase?: string
  ended?: { at: number; elapsed: number; ok: boolean; detail?: string; comparison?: string }
}

/** The last failing run's failures, for the failure pane. */
export type FailureList = {
  tool: string
  items: { title: string; message: string; where?: string }[]
}

/** The most serious problem `xcrew doctor` found at session start, and how many more there are. */
export type BandProblems = { isFailure: boolean; message: string; more: number }

declare module 'claude-code' {
  interface PluginState {
    xcrew: { run: BandRun | null; failures: FailureList | null; problems: BandProblems | null }
  }
}
