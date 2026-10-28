/** The run the band shows: going while `ended` is absent, then its outcome until the band hides. */
export type BandRun = {
  tool: string
  /** `scheme on destination`, as far as it's known. */
  target?: string
  startedAt: number
  ended?: { at: number; elapsed: number; ok: boolean; detail?: string; comparison?: string }
}

declare module 'claude-code' {
  interface PluginState {
    xcrew: { run: BandRun | null }
  }
}
