# Mod ideas

A working list of what Xcrew's mod could show or do. Nothing here is decided; entries move to the roadmap once someone picks them up. Dated October 2026, against Claude Code 2.1.312.

## What the mod shows today

| Where | Example | When |
| --- | --- | --- |
| Band above the prompt, in colour | `● test_sim · MyApp on iPhone 17 · 0:41`, then `✓ test_sim · 1:12 (avg 1:05) · 412 passed` | While a run is going, then its outcome for three minutes; success and failure in the theme's colours. Where no band draws (VS Code), the plain status line carries the run |
| Toast | `✓ test_sim · 1:12 (avg 1:05) · 412 passed` · `✗ BuildProject · 0:48 · FooView.swift:12 Cannot find 'bar' in scope` | When one ends, only where no band draws (VS Code): in the terminal a toast is one line on the notification bar for 4 s, and the band already shows the same line |
| Toast | `repaired Debug-iphonesimulator/SwiftMockKitMacros (index build) and retried BuildProject` | After a macro-plugin repair |
| Denied tool call | `XcodeWrite re-saves the whole generated project file…` | `XcodeWrite` in a Tuist or XcodeGen project |
| Command output | `/xcrew history` → `build_sim    avg 1:10 · last 1:20 · 2 runs` | `/xcrew doctor`, `repair`, `history`; no Claude turn |
| Tool description | `XcodeWrite` gains a line saying it's refused here | In a Tuist or XcodeGen project, when Claude first reads the tool |
| Hook spinner | `xcrew: preparing Xcode tooling` · `xcrew: checking Xcode macro plugins` | Session start; after a build failure with the plugin-kill message |

## What a mod can reach

From the [mods reference](https://code.claude.com/docs/en/plugins/mods/reference.md) and the [interface gallery](https://code.claude.com/docs/en/plugins/mods/gallery.md), the parts that matter for an Xcode tool:

- **Places to draw:** a band above the prompt (`AbovePrompt`), a pane beside the transcript (a sidebar in a wide fullscreen terminal, otherwise above the prompt), the status line, toasts, the spinner's word and suffix, the hint under the prompt, and Claude Code's own rows: a tool call (`ToolUse`, `ToolResult`, `ToolGroup`), a question dialog, a message.
- **Elements:** text, Markdown, code with syntax colours or a diff, buttons with hotkeys, text fields, pickers, a grid of coloured cells (`Raster`, for sparklines and heat maps), SVG in Desktop and VS Code, images in kitty, Ghostty and iTerm2.
- **Events:** every tool call before and after it runs (`tool.call`), each tool's description as Claude first reads it (`tool.describe`), turns, session start and end, prompt submission, the system prompt's sections.
- **Actions:** register `/commands` that run instantly with no Claude turn; register tools Claude can call; run or stream processes (`$.process.spawn` streams output); read files; keep data across sessions (`$.store`); timers; desktop notifications (`$.ui.notify`); sounds; ask the person a question mid-call (`$.ui.ask`); call a model (`$.model.complete`, `classify`).
- **Limits:** a hook's own work gets 10 s per event; `$.process.run` up to 10 min; redraws are throttled to 10 a second (30 in the terminal). Drawing works in the terminal, Desktop and VS Code, not in `claude -p` or cloud sessions. Some elements are terminal-only, others Desktop-only.

## What people build

From Anthropic's [sample mods](https://github.com/anthropics/claude-code-playground/tree/main/claude-code/mods) and community collections ([hamzafer/claude-code-mods](https://github.com/hamzafer/claude-code-mods), [awesome-claude-code-mods](https://github.com/karanb192/awesome-claude-code-mods)):

- **One-line bands above the prompt** are the most common shape: context fill (`token-weather`, `context-bar`), plan usage (`usage-meter`), one line per running subagent or background shell (`agent-radar`), what needs you (`glance`).
- **Live work as a line, the result as a toast:** `review-watch` shows one line per running code review, then lists the findings in a toast when it ends.
- **Guards that explain instead of refusing:** `blast-radius` holds `rm -rf` or a force push and shows what it would change, with proceed and cancel buttons; `merge-gate` holds `gh pr merge` until CI is green.
- **Panes for things worth a second look:** `mission-control` (agents, tool calls, touched files), `filetree` (git status, highlighting files as Claude touches them), `replay-theater` (step through the last turn's edits as diffs).
- **Conventions they share:** each mod does one visible thing; it hides when idle; it's opt-in; colour carries meaning (reads, writes, done); it states any token cost and terminal requirement up front.
- **Gap:** none of these watches builds or tests directly. The closest are the CI gate and the review watcher.

## Ideas

Effort: **S** a day or less, **M** a few days, **L** more, or needs research first.

### Build and test feedback

| Idea | Looks like | Surface | Data | Effort | Open questions |
| --- | --- | --- | --- | --- | --- |
| ~~Results in the toast~~ | Shipped: see what the mod shows today | | | | |
| ~~What's building~~ | Shipped: learned from `session_show_defaults` and the Xcode MCP's workspace and scheme answers | | | | |
| Build band | `last ✓ build 1:12 ▁▂▂▃▂ · ✗ tests 3 failed · 1 plugin repaired` | Band | `$.store` history | M | Hide when idle? The hamzafer conventions say yes, after a few minutes |
| Live progress | `BuildProject · 836/850 · 0:30` | Band | The Xcode MCP sends MCP progress (`Building • 836 / 850`), which Claude Code draws under the call | L | Blocked: a mod can't read it yet. The `ToolProgress` render site carries only the run-in-background hint; its docs say other kinds join later |
| ~~Slow-run alert~~ | Shipped: `(2× its usual 1:50)` in the toast and the band | | | | |
| ~~Done while you were away~~ | Shipped: runs of a minute or more notify, through the person's own notification settings | | | | |
| Durations from the servers | Averages and slow-run calls that leave out hook and permission time | Band, toast | MobileBuildMCP's `durationMs`, the Xcode MCP's `elapsedTime` | S | The band starts before PreToolUse hooks run, so a project's pre-build hook (one regenerating a Tuist workspace took ~20 s) lands in the first build's time and the average |
| Failure pane | Failing tests with their messages, the first compile errors as code | Pane, `/xcrew failures` | Result text | M | Same parsing as results in the toast |
| Restyled tool rows | A build call's row in the transcript shows `✓ 1:12 · AVDPortfolio` instead of raw output | `ToolResult` render site | Result | M | Must keep the raw output reachable; check how `ToolResult` rewriting behaves in VS Code |

### Health and setup

| Idea | Looks like | Surface | Data | Effort | Open questions |
| --- | --- | --- | --- | --- | --- |
| Doctor pane | Each check as a row with its fix, a button per fix that can run safely | Pane, `/xcrew doctor` | `xcrew doctor` | M | Which fixes are safe to run from a button (none that need sudo) |
| Setup form | Pickers for workspace, scheme, simulator, filled from `list_schemes` and `simctl` | Pane, `/xcrew setup` | MobileBuildMCP, `simctl` | M | Replaces the skill's question-and-answer flow; keep the skill for `claude -p` |
| Problem band | `⚠ Xcode MCP not approved · run /xcrew doctor` | Band | Session-start checks | S | Show once per session, dismissible |
| ~~Macro cause hint~~ | Shipped: the repair toast names the projects and the Tuist version that fixes them | | | | |

### Simulator and app

| Idea | Looks like | Surface | Data | Effort | Open questions |
| --- | --- | --- | --- | --- | --- |
| Simulator screenshot | The latest `screenshot` result as a picture | Pane | MobileBuildMCP's screenshot path | M | `Image` only draws in kitty, Ghostty, iTerm2; others get the alt text |
| Booted simulator | `iPhone 16 · iOS 26.5 · booted` | Status line | `simctl list --json` on a timer | S | Poll interval and its cost |
| UI-automation trail | Each tap and swipe Claude makes, with the element it hit | Pane | `tool.call` on the UI-automation tools | M | Is it useful, or noise? |

### Steering Claude

| Idea | Looks like | Surface | Data | Effort | Open questions |
| --- | --- | --- | --- | --- | --- |
| Tool descriptions that route | Shipped for `XcodeWrite` in generated projects. Build tools saying which server to prefer is still open | `tool.describe` | — | S | Could replace part of the session briefing, so routing costs no context until a tool loads |
| Explain-don't-refuse guard | `XcodeWrite` held with "This rewrites the generated project. Use Write instead? [Write it] [Cancel]" | `$.ui.ask` | — | S | Whether a held call beats a plain denial |

### Commands

| Idea | Looks like | Surface | Effort |
| --- | --- | --- | --- |
| ~~`/xcrew`~~ | Shipped: `doctor`, `repair`, `history` as text. `setup` stays the skill, since it needs Claude | | |
| `/xcrew history` pane | Durations per tool and scheme, as a table with sparklines (today: text, per tool) | Pane | M |

## Ground rules for anything that ships

- One visible thing per surface, hidden when idle, and quiet by default; nothing that interrupts unless it's worth it.
- Degrade per surface: a terminal-only element needs a fallback in Desktop and VS Code, and nothing draws under `claude -p`.
- Bookkeeping is best-effort and never fails a tool call (already true of the timing hook).
- No token cost unless it's stated; anything that adds text to Claude's context says how much.
- Parsing of a server's output is tested against captured real outputs and falls back to today's display when it doesn't match.
