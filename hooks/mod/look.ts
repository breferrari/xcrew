/** Claude's look at a failed UI test: answered by `xcrew look`, whose text Claude reads as it is. */
export const LOOK_TOOL = {
  name: 'look',
  description:
    "Xcrew: what a test run kept about a failed UI test's failure, on each test-plan configuration and device it failed on: the last steps leading to it, the failing step, the path of a PNG of the screen at the failure, to Read, the elements on screen when a query failed, with the queried one marked or named missing, and the configurations and devices it passed under. " +
    'With no test named, the failed UI tests of the newest MobileBuildMCP test run.',
  inputSchema: {
    type: 'object',
    properties: {
      test: { type: 'string', description: 'One test, as Suite/test.' },
      bundle: { type: 'string', description: 'A result bundle (.xcresult) to read instead of the newest test run, such as one the Xcode MCP made.' },
    },
  },
}

/** The full name Claude calls it by: a plugin's registered tool is `mcp__<plugin>__<name>`. */
export const LOOK_TOOL_NAME = 'mcp__xcrew__look'

export function lookArgs(input: Record<string, unknown>): string[] {
  const named = (key: string) => (typeof input[key] === 'string' && input[key] !== '' ? (input[key] as string) : undefined)
  const test = named('test'), bundle = named('bundle')
  return ['look', ...(test ? [test] : []), ...(bundle ? ['--bundle', bundle] : [])]
}
