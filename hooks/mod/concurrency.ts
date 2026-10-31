/** How far a scope's concurrency count must move, as a share of the count Claude last read, to be given again. */
export const CONCURRENCY_MOVE = 0.25

/** Whether a build's concurrency count is given: the first for its scope this session, or one that moved far enough. */
export function givesConcurrency(last: number | undefined, count: number): boolean {
  return last === undefined || Math.abs(count - last) >= last * CONCURRENCY_MOVE
}
