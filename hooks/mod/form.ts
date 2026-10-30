import type { ElementConstructor, RenderElement } from 'claude-code'
import type { SetupChoices, SetupForm, SetupPicks } from '../../types'
import type { Elements } from './band'

/** What Claude reads once after the person writes a config with the form: the session's MobileBuildMCP still has the old one. */
export const SETUP_FACT = 'The person wrote a new MobileBuildMCP config with /xcrew setup; MobileBuildMCP reads it when Claude Code next starts.'

/** What `xcrew setup` prints when it wrote the config, after its `xcrew: `. */
export const WROTE = 'wrote .mobilebuildmcp/config.yaml'

/** `/xcrew setup` where no surface draws pickers, as under `claude -p` or on the mobile app. */
export const NO_FORM = 'The setup form needs a session that draws pickers (the terminal, the desktop app or VS Code). /xcrew:setup, the skill, sets xcrew up from here.'

/** Whether a surface of the session draws the form's Select and Input: the mobile app draws neither yet. */
export function drawsForm(surfaces: readonly string[]): boolean {
  return surfaces.some(surface => surface === 'terminal' || surface === 'desktop' || surface === 'vscode')
}

/** The picks the form starts from: the choices' own, the container read, and the config's debugger backend. */
export function startingPicks(choices: SetupChoices): SetupPicks {
  return { ...choices.picks, ...(choices.container ? { container: choices.container } : {}), debuggerBackend: choices.config?.debuggerBackend === 'lldb-cli' ? 'lldb-cli' : 'dap', worktreeSimulator: 'clone' }
}

/** Whether writing replaces a config setup would otherwise keep: one xcrew didn't write, or one edited since. */
function replaces(choices: SetupChoices): boolean {
  return choices.config !== undefined && choices.config.owner !== 'xcrew'
}

/** The `xcrew setup` the picks make, each pick its option, `--force` only where the person is shown it replaces a config. */
export function setupArgs(choices: SetupChoices, picks: SetupPicks): string[] {
  const force = replaces(choices) ? ['--force'] : []
  if (choices.worktree) {
    const simulator = picks.worktreeSimulator === 'fresh' ? ['--fresh-simulator'] : picks.worktreeSimulator === 'share' ? ['--no-simulator'] : []
    return ['setup', '--worktree', ...simulator, ...force]
  }
  const option = (name: string, value: string | undefined) => (value ? [`--${name}`, value] : [])
  return [
    'setup',
    ...option('container', picks.container),
    ...option('app-scheme', picks.appScheme),
    ...option('bundle-id', picks.bundleID),
    ...option('ui-scheme', picks.uiScheme),
    ...option('test-scheme', picks.testScheme),
    ...option('test-simulator', picks.testSimulator),
    ...option('app-simulator', picks.appSimulator),
    // Always named: setup otherwise keeps the backend the old config had.
    ...option('debugger-backend', picks.debuggerBackend ?? 'dap'),
    ...force,
  ]
}

/** The form's elements, the terminal's, which draw pickers. */
export type FormElements = Elements & {
  Select: ElementConstructor<any>
  Input: ElementConstructor<any>
  Button: ElementConstructor<any>
}

/** Each picker's key, with the pick it sets. */
export const PICK_KEYS: Readonly<Record<string, keyof SetupPicks>> = { 'app-scheme': 'appScheme', 'ui-scheme': 'uiScheme', 'test-scheme': 'testScheme', 'bundle-id': 'bundleID', 'test-simulator': 'testSimulator', 'app-simulator': 'appSimulator', 'debugger-backend': 'debuggerBackend', 'worktree-simulator': 'worktreeSimulator' }

/** The schemes once per name, as `xcodebuild -scheme` takes them: a workspace's and its project's of one name are one. */
function schemesByName(schemes: SetupChoices['schemes']): SetupChoices['schemes'] {
  const byName = new Map<string, SetupChoices['schemes'][number]>()
  for (const scheme of schemes) {
    const seen = byName.get(scheme.name)
    byName.set(scheme.name, seen ? { ...seen, roles: [...new Set([...seen.roles, ...scheme.roles])] } : scheme)
  }
  return [...byName.values()]
}

/** What the form's controls do: a pick by its Select or Input key, the write, and closing it. */
export type FormActions = { pick: (key: string, value: string) => void; write: () => void; close: () => void }

const ROLE_WORDS: Record<string, string> = { app: 'builds the app', 'unit-tests': 'runs unit tests', 'ui-tests': 'runs UI tests' }

/** The setup form: facts and pickers, the write, and what the write said. */
export function formTree({ Box, Text, Select, Input, Button }: FormElements, form: SetupForm | null, act: FormActions): RenderElement {
  const close = Button({ key: 'close', label: 'Close', role: 'dismiss', onPress: act.close })
  const choices = form?.choices
  if (!form || !choices) return Box({ flexDirection: 'column', children: [Text({ color: 'subtle', children: [form?.unread ?? 'Reading the project…'] }), close] })
  const picks = form.picks
  const select = (key: string, label: string, options: { value: string; label?: string }[], value: string | undefined) =>
    Select({ key, label, options, ...(value === undefined ? {} : { value }), onSelect: (picked: string) => act.pick(key, picked) })
  const rows: RenderElement[] = []
  if (choices.worktree) {
    rows.push(Text({ children: ['This is a linked git worktree: its config is the main checkout\'s, with its own DerivedData and simulators.'] }))
    rows.push(select('worktree-simulator', 'Simulators', [
      { value: 'clone', label: 'clones of the main checkout\'s, while they\'re shut down' },
      { value: 'fresh', label: 'fresh ones on the same devices and runtimes' },
      { value: 'share', label: 'the main checkout\'s own' },
    ], picks.worktreeSimulator))
  } else {
    if (choices.containerProblem) rows.push(Text({ color: 'warning', children: [choices.containerProblem] }))
    if (choices.containers.length > 1) rows.push(select('container', 'Container', choices.containers.map(value => ({ value })), picks.container))
    if (choices.container && choices.schemes.length === 0) {
      rows.push(Text({ children: [`${choices.container} has no shared scheme. /xcrew:setup, the skill, can list the others with xcodebuild -list.`] }))
    } else if (choices.schemes.length > 0) {
      const schemes = schemesByName(choices.schemes).map(scheme => ({ value: scheme.name, label: `${scheme.name} · ${scheme.roles.map(role => ROLE_WORDS[role] ?? role).join(', ') || 'builds no app and runs no tests'}` }))
      const none = { value: '', label: 'none' }
      rows.push(select('app-scheme', 'App scheme', schemes, picks.appScheme))
      rows.push(select('ui-scheme', 'UI-test scheme', [none, ...schemes], picks.uiScheme ?? ''))
      // No "none": with no unit-test scheme passed, setup finds one itself.
      rows.push(select('test-scheme', 'Unit-test scheme', schemes, picks.testScheme))
    }
    if (choices.container) {
      rows.push(Input({ key: 'bundle-id', label: 'Bundle ID', placeholder: 'the project doesn\'t give one literally', value: picks.bundleID ?? '', onInput: (value: string) => act.pick('bundle-id', value), onSubmit: (value: string) => act.pick('bundle-id', value) }))
      if (choices.simulators.length === 0) {
        rows.push(Text({ color: 'warning', children: ['No iOS simulator is installed: add one in Xcode, then open the form again.'] }))
      } else {
        const simulators = choices.simulators.map(simulator => ({ value: simulator.name, label: `${simulator.name} · iOS ${simulator.runtime}${simulator.twoDisplays ? ' · two displays, where MobileBuildMCP\'s screenshot fails' : ''}` }))
        rows.push(select('test-simulator', 'Test simulator', simulators, picks.testSimulator))
        rows.push(select('app-simulator', 'App simulator', [{ value: '', label: 'the test simulator' }, ...simulators], picks.appSimulator ?? ''))
      }
      rows.push(select('debugger-backend', 'Debugger backend', [
        { value: 'dap', label: 'dap, MobileBuildMCP\'s default' },
        { value: 'lldb-cli', label: 'lldb-cli, which also runs LLDB commands such as expr' },
      ], picks.debuggerBackend))
    }
  }
  const config = choices.config
  rows.push(Text({ color: 'subtle', children: [
    !config ? 'There\'s no MobileBuildMCP config yet.'
      : config.owner === 'xcrew' ? `xcrew wrote the config${config.scheme ? `; it builds ${config.scheme}` : ''}.`
      : config.owner === 'edited' ? 'xcrew wrote the config, and it was edited since: writing replaces it, keeping a backup.'
      : 'The config isn\'t xcrew\'s: writing replaces it, keeping a backup.',
  ] }))
  const canWrite = choices.worktree || choices.container !== undefined
  const buttons = [
    ...(canWrite && !form.isWriting ? [Button({ key: 'write', variant: 'primary', label: replaces(choices) ? 'Replace config (a backup is kept)' : 'Write config', onPress: act.write })] : []),
    close,
  ]
  const written = (form.written ?? []).map(line => Text({ children: [line] }))
  return Box({ flexDirection: 'column', children: [...rows, ...(form.isWriting ? [Text({ color: 'subtle', children: ['Writing…'] })] : []), ...written, Box({ flexDirection: 'row', gap: 2, children: buttons })] })
}
