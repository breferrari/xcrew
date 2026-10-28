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

declare module 'claude-code' {
  interface PluginState {
    xcrew: { run: BandRun | null }
  }
}
