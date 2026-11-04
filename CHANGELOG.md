# Changelog

## Unreleased

## 0.16.0 — 2026-11-04

- A failing test run's failed tests come from its result bundle when it has one, in the order the run reported them: a failure MobileBuildMCP's text left out or didn't place is listed with its place, and the summary names the first failing test when the text named none. A crash the bundle files under `System Failures`, which MobileBuildMCP lists as `xctest (<pid>) encountered an error`, is the failure of the test its message names, listed once.
- Claude now sees every failure the result bundle records, including ones MobileBuildMCP's text didn't list. Each gets its line under Test Failures, with its place and notes. A test in a nested suite gets its place, crash note and images, which xcresulttool gives only under the name the bundle has for it, from its outermost suite; when the text's name matches several nested tests, each failed one is listed once under its own name, with a note saying what MobileBuildMCP reported. The `look` commands Claude is offered name such a test, one that takes arguments or a crash's case as the bundle does, quoted so a shell runs them as written, and each names the bundle it reads.
- A failing test run's summary no longer names a test the result bundle records as passed, skipped or an expected failure in every entry, test plan configuration and device, as one a retry passed: that test is no failure, and a note names it with what the bundle records. Any other test MobileBuildMCP lists as failed stays a failure as MobileBuildMCP gives it, as one the bundle has no entry for, or records as `unknown` or with no result in any entry, and the note says what the bundle records. Such a test, as one the bundle records passed in one test bundle and `unknown` in another, no longer turns green in the ledger.
- `xcrew space` says how much this project's MobileBuildMCP storage takes and which class takes the most, and no longer measures it against a 40 GB budget; `XCREW_STORAGE_BUDGET_GB` is gone.
- The evidence block now lists everything it used to cut short with "no list of them is kept": every changed line not run, every unreached target, every file outside the coverage or changed after it, every run's finish time and every warning in changed lines. The session briefing and a test run of no tests name a few test plans and the schemes that share one, and `xcrew plans` lists every one; the briefing puts the project card before them, so a large app's plans can't push it out.
- The CLI build xcrew starts as a session begins now finishes and is put in place even if that session ends first, or its terminal closes. Before, it could be lost after compiling, so the next session built again, and it left a file behind in xcrew's cache. A build stopped with Ctrl-C leaves nothing behind, and one stopped harder is cleared by the next build.

## 0.15.0 — 2026-11-03

- No time limit of xcrew's own cuts its work any more. A report on a build or test result, the evidence block, a `/xcrew` command, the CLI run from a terminal or by Claude through Bash, and every command xcrew starts go to their end, however long that takes. Before, each command had a limit of its own, among them a report's 120 s, the evidence's 300 s, the doctor's Xcode MCP handshake's 10 s, the session briefing's MobileBuildMCP read's 2 s and `xcrew space`'s 30 s a folder. The only limits left are Claude Code's and GitHub's own. Stopping xcrew's CLI, or Ctrl-C, stops the programs it started too.
- Nothing xcrew reads is cut to a size any more: every failed test is looked up, every skipped test the result leaves out is added, `look` checks every failed test for a recording, every scheme's test plan is read, a run's whole log is read for its verdict, and a pin file of any size is read. A list that names a few and counts the rest says where they all are, or that no list of them is kept, and the card at a session's start keeps every line. The ledger keeps each failure's whole message and shows its first line.
- Ending, clearing or resuming a session no longer builds xcrew's CLI, which Claude Code cancelled after an update ("Hook cancelled"), as it gives a session's end 1.5 s in all: the end removes what the session recorded in one step and starts nothing else. A session's start no longer waits for the build either: it says the CLI is being built, and the briefing on the project follows with the next turn.
- After an update, xcrew's CLI is built once, by a lock the system lets go when its holder ends, so a build is never started beside another, and a build that fails is said to every call waiting on it, with the compiler's reason, rather than run again by each. `/xcrew doctor` and any call made while the CLI is still being built wait for that build and answer whole; if you ran 0.14.0, they answered "couldn't answer: it failed" there.
- When xcrew can't read something it needs, as a test run's report, the checkout's branch or the doctor's problems, it says so, with why, rather than going on without it. Claude reads it with the next result of a build, a test, an edit or another Xcode tool, and the line above the prompt shows it for a couple of minutes; one that keeps failing in the background is said once until it reads again. `/xcrew` commands, the affected tests, the setup form and the evidence block say it too. Before, the note was simply missing.
- `/xcrew doctor` says what it waits on while it waits, in the status line: a new Xcode MCP bridge waiting on Xcode's approval dialog, with what to do. Its handshake with that bridge stops waiting as soon as the bridge ends without answering.
- A run moved to the background is followed until its notification however quiet its log and however many runs are in the background; before, one whose log went quiet for 90 s, or past the 20 newest, was dropped. The MobileBuildMCP server waits for a pinned Xcode however long finding it takes. A read for the line above the prompt no longer starts while its last one is still going.
- `/xcrew setup` and `xcrew setup --choices` show how many unit-test and UI-test targets each scheme runs by default. When the config has no `unit` profile for its container, or you pass `--test-scheme ''`, setup gives `unit` the scheme that runs the most, or lists the schemes that tie for the most, rather than the app's scheme that may test one module; a `unit` profile the config has stays as it is. The `/xcrew setup` form starts from the profiles your config has, and a scheme that builds several apps names the one it launches.
- After an update and `/reload-plugins`, the CLI's build that xcrew starts as the plugin loads runs to its end, and no command stops it. Before, a short read of the session's start could stop the build, leaving the next command to build again.
- A test run's report reads the run's test list once: on a failing run of a large suite, repeated with `-test-iterations`, the list's questions took a third of the time they did, as each question read it again.
- A build or test run that overlapped another worktree's build or test is kept out of its usual time, which the line above the prompt measures runs against, and isn't measured against it either: it ran slower for sharing the Mac. Before, two checkouts testing at once raised each other's usual time. The check runs after the result is returned, so no result waits on it; the run's ending on the line above the prompt waits for it, a few tens of milliseconds.
- The evidence block's changed-line coverage counts a line as run when any test run that compiled its file as it is now ran it, and names those runs. A run that started before the file last changed, as one from another branch or before a later commit, doesn't count for it, nor does a run of no tests. Before, it read only the newest run, which could have tested another module or nothing.
- The evidence block reads the branch's test runs side by side, with as many of their commands at once as the Mac has performance cores, the newest runs' commands first. Before, it read the runs one after another, so a branch with many runs took longer to read.
- Rebuilding the CLI no longer removes xcrew's own folders in its cache, such as the session stamps, the failed tests' images and the cards, when nothing new was added to one for two weeks: its cleanup removes only old builds.
- The evidence block for a pull request no longer lists usual run times, and the card at a session's start no longer lists them either: it keeps the tests still red and, when a full test run is slow, the selections run before it. The line above the prompt still measures runs against their usual time.
- The note on a corrupt module cache, which offers the command that removes the two cached folders, says that deletes part of DerivedData, so it's yours to agree to. Before, Claude could read it as a fix to run without asking.
- The note on a build database another xcodebuild holds, which gives the `kill` that stops it, says the build may be yours, so stopping it is yours to agree to. The doctor's line on an old `.xcodebuildmcp/` folder says the same of removing it, and gives the command.
- Where xcrew offers `xcrun simctl delete`, for a worktree's simulator, one left from a removed worktree or the unavailable ones, it says deleting loses the apps installed on them and their data, so it's yours to agree to.
- Wherever else xcrew gives a command that removes or overwrites something of yours, `xcodes uninstall`, the MobileBuildMCP purge's `--delete`, the old XcodeBuildMCP's uninstall, `defaults write` for unsigned agents and `xcode-skills --force`, it says what's lost and that it's yours to agree to, before the command.
- A test run refused because `-only-testing:` names a target its scheme doesn't test gets a note naming that scheme, a shared scheme that runs the target by default, and the `session_set_defaults` call that switches to it. Before, nothing said why, and the note for a run of no tests named other causes.
- A test that crashed with no crash log, in a run of that test alone, has its note name `-parallel-testing-enabled NO` in `extraArgs`, rather than suggest running it alone again.
- At a session's start, the run times, test counts and ledgers of a checkout that's gone, as a worktree you removed, are dropped. A checkout on a drive that isn't connected, or one macOS won't let xcrew look at, keeps its data. Before, they stayed until no run had updated them for two weeks.
- In an Xcode project, the coverage note no longer lists a changed test file as missing from the run's coverage. A run of one module's tests had named a changed UI test file it never built.
- A build or test result Claude reads lists only the warnings in lines your branch changed, and counts the rest in one line that says where the full list is: the saved result, or the run's build log. That holds for a failed run moved to the background too. Outside git, every warning stays listed.
- A failed test run that Claude Code moved to the background is read like the same run in the foreground: its failing tests are named and recorded, with xcrew's notes. Before, its notification came back as MobileBuildMCP's whole text, with nothing of xcrew's.
- A run that names no scheme is recorded under the scheme its log names, with its duration, test total and failed runs, when Claude Code moved it to the background before its log appeared, or it ended before xcrew read its log. A notification whose result can't be read falls back on that log. Before, both runs recorded nothing.
- Tests that xcrew 0.11.0 or earlier recorded as red then green leave the ledger, rather than showing under "Still red" until a run lists them as passed. One marked flaky stays red with its mark, as it still needs its passes. The ledger rebuilds from new runs.
- The doctor no longer asks for a restart that isn't needed, or says a session's rules weren't given, when the two things a session records as it starts were written at once.
- A long result Claude Code saved to a file stays saved when xcrew shortens it but it's still long. Before, any change xcrew made, as trimming its warnings, put the whole result back into the conversation.
- After `xcrew setup`, a running MobileBuildMCP gets the profiles as the config holds them, as MobileBuildMCP itself reads a config edited by hand or rewritten by it. Before, a quoted profile name made it create a second profile, a comment line dropped the profiles after it, a long path wrapped onto the next line was cut short, and a path written from the project root carried a `/./`.
- `xcrew setup` and the doctor no longer ask for a restart when only the profiles changed in a config with a comment line among them. On a file system that keeps whole seconds, setup now asks for the restart that changed server settings need, as it reads the change from what it wrote. Before, it compared the file's time with its own start, and such a file system could round that time down to before setup began, so it asked for no restart.
- When xcrew lists only the warnings in lines your branch changed, the result's `Warnings (N):` heading counts the warnings still listed, and with no heading the line counting the rest goes after the run's header, not above it. A build and run that Claude Code moved to the background no longer shows as passed, on the line above the prompt or in what's recorded, once its build succeeds: a failed build ends it, and otherwise its notification says how it ended.
- When a UI test's query found nothing and the failure has a screen, `xcrew look` says the elements it lists are the app's only: a system alert covering the app shows only in the screenshot.
- A red test that the newest run of its scope didn't run, as one deleted or renamed since it failed, says so in the ledger and the evidence block, rather than reading as still failing.
- `xcrew project`'s usage no longer names `--xcuserstate`, which it doesn't take. Keeping a failed test's images no longer measures every image kept in the last two weeks: each run's size is recorded once.
- `/xcrew doctor` runs its checks once, not twice: its report and the problems on the line above the prompt come from the same run.
- Following a long test run's log costs less each second: what xcrew keeps between reads is a quarter of its size for a large suite, and it no longer reads the log's start and end again each time.
- `look` lists the elements on screen once when a test failed alike under several configurations of a test plan: each later one says its screen held the same, in one line.
- A test marked flaky that a plain test run fails starts its passes in a row over. Before, it kept them, and could turn green although it had failed since its last pass.
- A test marked flaky reads "passed 0 of the 4 needed in repeated runs since", saying that only a repeated run's passes count, so a single pass no longer reads as a wrong count. The ledger, the card, `/xcrew flaky` and the evidence block say it alike.
- xcrew's notes on which Xcode builds, on the project's pin, on a corrupt module cache and on a build database another build left locked state their fix as a fact rather than an order, as its other notes do.
- The `elsewhere:` line above the prompt, showing another worktree's runs, dims only its label: the runs read in your theme's text colour.

## 0.14.2 — 2026-11-03

- `mcs sync` no longer removes the app and UI-test profiles `/xcrew setup` added to `.mobilebuildmcp/config.yaml`, nor moves its container. mcs runs `xcrew setup` with only its own answers on every sync, and setup rewrote the config from those alone. Now setup keeps the container, schemes, simulators and bundle ID the config holds, and mcs's answers only add a profile the config lacks. An option you pass names another choice; an empty one drops that profile, or for `--test-scheme` lets setup pick. `--force` still replaces a config edited by hand, keeping a backup, and now keeps the profiles' choices too.

## 0.14.1 — 2026-11-03

- xcrew returns to how 0.13.1 worked: 0.14.0's changes are taken back, as in 0.14.0 `/xcrew doctor` could fail without saying why. Everything listed under 0.14.0 below is withdrawn, and comes back in a later release.

## 0.14.0 — 2026-11-03

- `/xcrew setup` and `xcrew setup --choices` show how many unit-test and UI-test targets each scheme runs by default, and setup gives the `unit` profile the scheme that runs the most, rather than the app's scheme that may test one module. So running `xcrew setup` again without `--test-scheme` can move `unit` from the app's scheme to a workspace scheme, or list the schemes that tie for the most, where before it picked the app's scheme. The `/xcrew setup` form starts from the scheme your config's `unit` profile has, and setup keeps a config edited by hand unless you pass `--force`. A scheme that builds several apps names the one it launches.
- A test run's report reads the run's test list once: on a failing run of a large suite, repeated with `-test-iterations`, the list's questions took a third of the time they did, as each question read it again.
- No command xcrew runs has a time limit of its own any more: each takes what's left of its call's deadline, which a change to the Mac's clock doesn't move. The session-start hook's work after the CLI's build has 10 s, as Claude's first answer waits on it; before, the briefing's MobileBuildMCP version read had 2 s and its simulator read 1 s, and `xcrew space` gave each folder 30 s. Reads nobody waits on, as the line about other worktrees, have the process's own 30 s, and a timer's read no longer starts while its last one is still going. The doctor's Xcode MCP handshake stops waiting as soon as the bridge ends without answering, and a pinned Xcode's lookup cut short at the MobileBuildMCP server's start is recorded as timed out, not as a pin nothing installed matches.
- What xcrew adds to a build or test result has 10 s from when the result came back, any wait for the CLI's build included, and each command the CLI starts has what's left. A `/xcrew` command, the evidence and the CLI run from a terminal or by Claude through Bash have 120 s. When that time cuts something short, the result says which of xcrew's notes it left out, in one line; the report reads the failures before the changed lines' coverage. Before, each step had a limit of its own: a report could take 120 s, and the evidence 300 s. Asked for while the CLI is still being built, the affected tests say so, rather than that the whole suite covers the changes.
- After an update and `/reload-plugins`, the CLI's build that xcrew starts as the plugin loads runs to its end under no command's time limit, and no command builds under its own time or stops a build: one that finds none waits for it within its own time. Before, a short read of the session's start could stop the build, leaving the next command to build again.
- A build or test run that overlapped another worktree's build or test is kept out of its usual time, which the line above the prompt measures runs against, and isn't measured against it either: it ran slower for sharing the Mac. Before, two checkouts testing at once raised each other's usual time. The check runs after the result is returned, so no result waits on it; the run's ending on the line above the prompt waits for it, a few tens of milliseconds.
- The evidence block's changed-line coverage counts a line as run when any test run that compiled its file as it is now ran it, and names those runs. A run that started before the file last changed, as one from another branch or before a later commit, doesn't count for it, nor does a run of no tests. Before, it read only the newest run, which could have tested another module or nothing.
- The evidence block reads the branch's test runs side by side, with as many of their commands at once as the Mac has performance cores, the newest runs' commands first. Before, it read the runs one after another, so a branch with many runs took longer to read.
- Rebuilding the CLI no longer removes xcrew's own folders in its cache, such as the session stamps, the failed tests' images and the cards, when nothing new was added to one for two weeks: its cleanup removes only old builds.
- The evidence block for a pull request no longer lists usual run times, and the card at a session's start no longer lists them either: it keeps the tests still red and, when a full test run is slow, the selections run before it. The line above the prompt still measures runs against their usual time.
- The note on a corrupt module cache, which offers the command that removes the two cached folders, says that deletes part of DerivedData, so it's yours to agree to. Before, Claude could read it as a fix to run without asking.
- The note on a build database another xcodebuild holds, which gives the `kill` that stops it, says the build may be yours, so stopping it is yours to agree to. The doctor's line on an old `.xcodebuildmcp/` folder says the same of removing it, and gives the command.
- Where xcrew offers `xcrun simctl delete`, for a worktree's simulator, one left from a removed worktree or the unavailable ones, it says deleting loses the apps installed on them and their data, so it's yours to agree to.
- Wherever else xcrew gives a command that removes or overwrites something of yours, `xcodes uninstall`, the MobileBuildMCP purge's `--delete`, the old XcodeBuildMCP's uninstall, `defaults write` for unsigned agents and `xcode-skills --force`, it says what's lost and that it's yours to agree to, before the command.
- A test run refused because `-only-testing:` names a target its scheme doesn't test gets a note naming that scheme, a shared scheme that runs the target by default, and the `session_set_defaults` call that switches to it. Before, nothing said why, and the note for a run of no tests named other causes.
- A test that crashed with no crash log, in a run of that test alone, has its note name `-parallel-testing-enabled NO` in `extraArgs`, rather than suggest running it alone again.
- At a session's start, the run times, test counts and ledgers of a checkout that's gone, as a worktree you removed, are dropped. A checkout on a drive that isn't connected, or one macOS won't let xcrew look at, keeps its data. Before, they stayed until no run had updated them for two weeks.
- In an Xcode project, the coverage note no longer lists a changed test file as missing from the run's coverage. A run of one module's tests had named a changed UI test file it never built.
- A build or test result Claude reads lists only the warnings in lines your branch changed, and counts the rest in one line that says where the full list is: the saved result, or the run's build log. That holds for a failed run moved to the background too. Outside git, every warning stays listed.
- A failed test run that Claude Code moved to the background is read like the same run in the foreground: its failing tests are named and recorded, with xcrew's notes. Before, its notification came back as MobileBuildMCP's whole text, with nothing of xcrew's.
- A run that names no scheme is recorded under the scheme its log names, with its duration, test total and failed runs, when Claude Code moved it to the background before its log appeared, or it ended before xcrew read its log. A notification whose result can't be read falls back on that log. Before, both runs recorded nothing.
- Tests that xcrew 0.11.0 or earlier recorded as red then green leave the ledger, rather than showing under "Still red" until a run lists them as passed. One marked flaky stays red with its mark, as it still needs its passes. The ledger rebuilds from new runs.
- The doctor no longer asks for a restart that isn't needed, or says a session's rules weren't given, when the two things a session records as it starts were written at once.
- A long result Claude Code saved to a file stays saved when xcrew shortens it but it's still long. Before, any change xcrew made, as trimming its warnings, put the whole result back into the conversation.
- After `xcrew setup`, a running MobileBuildMCP gets the profiles as the config holds them, as MobileBuildMCP itself reads a config edited by hand or rewritten by it. Before, a quoted profile name made it create a second profile, a comment line dropped the profiles after it, a long path wrapped onto the next line was cut short, and a path written from the project root carried a `/./`.
- `xcrew setup` and the doctor no longer ask for a restart when only the profiles changed in a config with a comment line among them. On a file system that keeps whole seconds, setup now asks for the restart that changed server settings need, as it reads the change from what it wrote. Before, it compared the file's time with its own start, and such a file system could round that time down to before setup began, so it asked for no restart.
- When xcrew lists only the warnings in lines your branch changed, the result's `Warnings (N):` heading counts the warnings still listed, and with no heading the line counting the rest goes after the run's header, not above it. A build and run that Claude Code moved to the background no longer shows as passed, on the line above the prompt or in what's recorded, once its build succeeds: a failed build ends it, and otherwise its notification says how it ended.
- When a UI test's query found nothing and the failure has a screen, `xcrew look` says the elements it lists are the app's only: a system alert covering the app shows only in the screenshot.
- A red test that the newest run of its scope didn't run, as one deleted or renamed since it failed, says so in the ledger and the evidence block, rather than reading as still failing.
- `xcrew project`'s usage no longer names `--xcuserstate`, which it doesn't take. Keeping a failed test's images no longer measures every image kept in the last two weeks: each run's size is recorded once.
- `/xcrew doctor` runs its checks once, not twice: its report and the problems on the line above the prompt come from the same run.
- Following a long test run's log costs less each second: what xcrew keeps between reads is a quarter of its size for a large suite, and it no longer reads the log's start and end again each time.
- `look` lists the elements on screen once when a test failed alike under several configurations of a test plan: each later one says its screen held the same, in one line.
- A test marked flaky that a plain test run fails starts its passes in a row over. Before, it kept them, and could turn green although it had failed since its last pass.
- A test marked flaky reads "passed 0 of the 4 needed in repeated runs since", saying that only a repeated run's passes count, so a single pass no longer reads as a wrong count. The ledger, the card, `/xcrew flaky` and the evidence block say it alike.
- xcrew's notes on which Xcode builds, on the project's pin, on a corrupt module cache and on a build database another build left locked state their fix as a fact rather than an order, as its other notes do.
- The `elsewhere:` line above the prompt, showing another worktree's runs, dims only its label: the runs read in your theme's text colour.

## 0.13.1 — 2026-11-02

- `/xcrew doctor` checks the session it runs in, so `xcrew/briefing-current` and `xcrew/mod-loaded` say something there. In 0.13.0 they always skipped with "not run from a Claude Code session".
- `mcs doctor` no longer offers `defaults write … IDEAllowUnauthenticatedAgents` as the fix for "Claude Code approved in Xcode", which approved nothing; its MobileBuildMCP version fix is the CLI's own, `brew upgrade mobilebuildmcp`. The README, SECURITY.md and the reference skill now describe the doctor as it is: no network request, no storage scan.
- `xcrew/briefing-current` passes as "the running xcrew's", without a version, so the README's sample doctor report stays true across releases.

## 0.13.0 — 2026-11-02

- After `xcrew setup`, a running session builds and tests with the new profiles at once: setup prints the `session_set_defaults` calls that give them to MobileBuildMCP, and the doctor asks for a restart only when the config's tool groups or server settings changed. A new worktree session needs no restart to build and test after `xcrew setup --worktree`.
- The doctor says when a session's rules are an older xcrew's than the one running, as after a plugin update in an open session, `/reload-plugins` included, and when xcrew's mod hasn't reported in the session, which leaves its notes, tools and the line above the prompt off. Both checks run only from inside a Claude Code session.
- Before setup, the doctor names the generate command along with setup in a checkout whose Tuist or XcodeGen project isn't generated yet, as a new worktree's: setup alone left nothing to build.
- The briefing names one command for setting up a worktree's session, `xcrew setup --worktree`, as the doctor and the line above the prompt do, and the setup skill starts there in a worktree.
- A test run whose filter matched tests that then didn't execute ends on the line above the prompt as `✗ test_sim · 7:49 · 1 selected, none ran`, rather than `no tests ran`, which read as a filter that matched nothing.
- The ledger shows a red test's newest failure message, so a test that has since failed every repeated run reads as a real failure, while its first red's date stays. Before, it kept the message of its first failure.
- After `/clear` or `/resume`, the new conversation starts with a clean slate: a pin to suggest is named again on the next failing build it may explain, and the doctor's warnings show again from its first prompt. Before, they counted as already said.
- A test run's report reaches Claude about 0.6 s sooner: a result bundle without coverage is no longer handed to `xccov`, and one with coverage asks it one question fewer.
- The line above the prompt reads a running build's or test's log on from where its last look stopped, rather than the whole log every second: on a 31 MB log each look takes about 10 ms instead of 50.
- A build or test run moved to the background stops being followed once its log never appears, or once more calls wait for their notifications than xcrew keeps. Before, its once-a-second read of the run's phase went on for the rest of the session.
- Which Xcode CI selects is read through the local composite actions a workflow uses (`uses: ./…`), however deep, so a bare `xcodes select` in one counts as CI selecting the project's `.xcode-version`. Before, a workflow that chose its Xcode in a local action was taken to name none.
- `/xcrew timings` lists the build, test and run calls that waited a second or more before they reached their server, with how long each step before the call took, so a slow start can be traced to its step.
- xcrew's cache stays smaller: an installed plugin's build no longer leaves its 200 MB scratch folder behind, each old plugin version's source stamp goes after two weeks, failed tests' images are capped at 200 MB, oldest run first, and a running log's kept reading goes a day after its run.
- A test run asks `xcrew project --branch` once for its ledger and card where it asked up to four times: an answer under five seconds old is shared, and a Bash call, which may switch branches, drops it.
- Editing a YAML file, such as a CI workflow, in a project XcodeGen doesn't generate no longer starts two `xcrew` calls on the edit's path; `project` says whether the project reads YAML (`readsYaml`).

## 0.12.0 — 2026-11-02

- The ledger and the evidence block mark a test passed only when the run's results list it as passed, so a test deleted or renamed since it failed no longer shows as fixed. Before, a later run whose selection included the test was taken to have passed it. A test an older version marked fixed that way shows as failing again until a run lists it as passed.
- A test marked flaky turns green only after enough passes in a row from repeated runs: enough that, failing at the rate it was seen failing, it would pass them all under 5% of the time (14 after failing 1 of 5 runs). The ledger, the card, `/xcrew flaky` and the evidence say how many it has, `passed 10 of the 14 needed since`. Before, one repeated run passing it every time turned it green.
- A build or test run Claude Code moves to the background stays on the line above the prompt, going, with its time, gauge and phase and marked as in the background, until its log's verdict or its notification ends it. A run whose log stops with neither leaves after a minute and a half. Before, it showed `no result yet` and dropped off while it went on.
- Installed with mcs, xcrew needs mcs 2026.10.31 or later, which loads a pack's plugin with its hook modules, so the mod's line above the prompt and its tools load too. After upgrading mcs, run `mcs sync` once.
- The doctor checks only what xcrew can't run without, its installation and the toolchain, and reaches no network: whether a newer Xcrew is out is the plugin system's to say, and whether Xcode accepts unsigned agents is said once by `xcrew setup`.
- The doctor no longer scans the disk: this project's MobileBuildMCP storage against its budget, and the simulators a removed worktree left behind, are in `xcrew space`, which shows them when you ask.
- The line above the prompt no longer runs the doctor again every 30 seconds after a prompt: the doctor runs at session start, after setup, and when `/xcrew doctor` asks, which also clears a problem fixed since.
- What the doctor checked ahead of time about which Xcode builds is said on a failed MobileBuildMCP build or test it can explain, one whose errors another SDK or toolchain gives: CI on another Xcode, a pin to suggest, and an open Xcode other than the one building, each only when it holds. The doctor no longer checks them, nor for an xcodebuild left running, which a build that finds its database locked already names.
- The doctor's `xcode-mcp/macro-copy-phase` check is gone: Tuist 4.203 removed the copy phase it looked for.
- The doctor's `simulators/memory` check is gone: its two measures of a simulator's memory disagreed by about 40%, so neither could be trusted as the figure.
- `affected` names the one scheme that tests everything a change reaches when that's most of the suite, rather than listing hundreds of module schemes. A narrower change still lists the schemes that test only selected targets, the first ten named and the rest counted, and a target none of them tests is named with the scheme that tests it with the fewest others, as `` `Mixed` tests AppUITests with 1 more``.
- A failing MobileBuildMCP test run repeated with `-test-iterations` lists each failing test with its message and file and line, from the result bundle, and lists each test once with its runs counted, rather than once per run. A failing test run no longer lists the coverage runtime's `default.profraw` error, as a failing build already didn't.
- A test run moved to the background whose result Claude Code saved for its size reaches Claude shortened: its build warnings are counted and pointed to in the saved file, with its errors, failures and counts kept. Before, a run with hundreds of warnings came back as MobileBuildMCP's whole result, about 120,000 characters.
- A test that crashed is listed as that test's failure when the result bundle files the crash under `System Failures`, as it can on iOS 26: in the failures pane, on its row and in the ledger. Before, the run showed a failure but named no test.
- A MobileBuildMCP test run whose filter matched tests that then didn't execute says so in its note to Claude, naming the test plan's configurations when it has several, rather than blaming a filter that matched nothing. A run of no tests that doesn't list what it matched names every cause that does this, without claiming one.
- A Swift Testing run through a test plan of several configurations counts its tests through the first configuration and then says `testing`, rather than counting past its total as `testing · 10 done`.
- A MobileBuildMCP run that names no scheme keeps its time, test count and red-to-green record under the scheme its own log says it built, so a run is never filed under a scheme xcrew guessed wrong. A run whose log never appears is shown but not recorded.
- A build held back after a manifest edit is undone says why: a build was refused for that edit, so the project may have been generated from it since, and the next build goes through. An edit that puts the manifests back no longer asks for a generate before the next build.
- `xcrew space` says its sizes are decimal, as Finder counts them, and gives this project's total in `du -h`'s GiB too, so the two read alike, and says when a build is writing to a workspace as it's measured. The dry run `xcrew space` suggests starts with test products, counted in bundles with their size each, and names DerivedData apart, since it costs a cold build.
- `xcrew space` stops naming a gone project's MobileBuildMCP workspace with a purge once it holds only what `mobilebuildmcp purge` keeps, logs from the last hour and its state, and counts such folders on one line instead. Before, the same purge was offered again though it freed nothing.
- A screenshot of a simulator with two displays gets its note again, naming `simctl`'s `--display` option. simctl gives its reason on the error's third line, which xcrew didn't read, so the note never showed.
- The session's routing rules say a git worktree gets a session of its own, `claude --worktree <name>` set up there with `/xcrew:setup`, since each session's MobileBuildMCP serves its own checkout, and that a build or test run from Bash, the `mobilebuildmcp` CLI's included, gets no timing, ledger or line above the prompt.
- In a Tuist or XcodeGen project, the doctor says a worktree's workspace isn't generated in this checkout yet and names the generate command (`tuist install && tuist generate --no-open`, or `xcodegen generate`), rather than calling it moved or renamed and offering `xcrew setup`.
- In a worktree set up by `xcrew setup --worktree`, the doctor checks its simulators by the ID the config names, and fails when one is gone. Before, it skipped them, saying no simulators were named.
- `xcrew space`'s part on the simulators setup made for worktrees says "none of those made for this repository's worktrees is left" once every simulator setup made for them is deleted, rather than "0 made …, each still there".
- The session's start no longer says "and at least 0 more test plans" when it stopped reading a large project's schemes with every plan it found already named; it says the schemes past the first 50 weren't read.

## 0.11.0 — 2026-10-31

- The line above the prompt counts a serial XCTest run's and a Swift Testing run's progress while it goes, `testing N of M`, as MobileBuildMCP's result counts their tests. Before, it showed no count until the tests were done.
- A test that failed and then passed when retried (`-retry-tests-on-failure`) no longer shows as a failure in the failures pane or red in the ledger. MobileBuildMCP's text lists it among the failures, but its own count, like the result bundle, counts it passed.
- The line above the prompt no longer counts a test run past its total when the run tests a case more than once (`-test-iterations`, `-retry-tests-on-failure`, a test plan's configurations): it counts through the first pass, then says `testing`. A cancelled Swift Testing test counts as skipped, as MobileBuildMCP counts it.
- Once a test run's build is done, the line above the prompt says `testing` until the tests start, rather than the build's last step.
- A passing MobileBuildMCP test run says how many tests passed, on the line above the prompt and its row, and the next run of that scheme counts its progress out of that total. Before, a passing run showed no count.
- A MobileBuildMCP test run whose `-only-testing` or `-skip-testing` filter matches no test reads as no tests ran, with a note saying why, rather than as a pass, and a passing run whose count MobileBuildMCP left out shows its count.
- The line above the prompt names the scheme and simulator of the MobileBuildMCP profile in use after Claude switches profiles, and what xcrew keeps per profile (usual times, test counts, the loop budget) follows the switch. Before, with MobileBuildMCP 2.7.1, neither happened.
- The note to Claude names a Swift Testing test that recorded a known issue as one (`withKnownIssue`), not as an XCTest expected failure (`XCTExpectFailure`).
- A test that crashed on a Swift runtime error is listed alone in the failures pane and on its row, its error in its crash note. Before, the error came first, listed twice as failures of its own.
- A skipped Swift Testing test's reason no longer starts with `Test skipped:` in the result Claude reads.
- A build or test run a subagent started says which, on the line above the prompt and on its row in the transcript, by the subagent's own description, quoted: `· by "Fix login tests"`.
- `xcrew graph` no longer reads imports from a Swift file a target only copies as a resource, and `xcrew graph --owner` names no target that builds one; `affected` still counts such a file, since a changed resource changes its target's bundle.
- The line above the prompt adds a dim line for the builds and test runs going in the project's other worktrees, each with its worktree, tool and phase, as `elsewhere: feature · test_sim · testing 120 of 959`.
- The full `xcrew doctor` adds up this project's MobileBuildMCP storage across its checkouts and worktrees and, past a budget of 40 GB (`XCREW_STORAGE_BUDGET_GB` sets another), names the largest workspace with the `mobilebuildmcp purge --dry-run` command that lists what it would delete. It also names the workspaces on this Mac whose project folder is gone. It deletes nothing, and stays out of the line above the prompt, since the report walks every file.
- `/xcrew flaky` lists the tests marked flaky on the branch checked out, each with how many of its runs failed and the repeated run that found it flaky, straight from the ledger, without a turn.
- When a build or test failed because of the Mac, as with a corrupt module cache or a missing simulator, the failures pane opens with that cause and its fix, as Claude read it, ahead of the failing tests and compile errors, and the line above the prompt points to the pane even when the run listed no errors.
- `xcrew doctor` names a simulator `setup --worktree` made whose worktree is gone, or whose runtime the Mac has lost, with the `xcrun simctl delete` command that removes it; it deletes nothing, and judges only what setup recorded making, never a name. It also weighs the booted simulators against this Mac's memory, by two measures that disagree, and names them in the full doctor, off the line above the prompt, once the lower one passes three quarters of it.
- A MobileBuildMCP build or test that names no scheme keeps its times under the scheme it built: the profile chosen during the session, and when Xcode started MobileBuildMCP, the scheme selected in Xcode, followed as it changes unless `disableXcodeAutoSync` is set. Runs of different profiles no longer share usual times, test counts or the loop budget.
- A failing MobileBuildMCP test run now gets xcrew's notes: each failure's place, a crash's Swift error and line, and skip reasons. Before, xcrew didn't recognise a real test run's result as one. A run repeated with `-test-iterations` lists each test once with how many runs failed, with skip reasons from the result bundle, and a crash shows the Swift error and the test's line.
- A build or test that Claude moves to the background now ends like any other when its task does: its result is read and shortened, with xcrew's notes, and its time, its failures, the red-to-green ledger and the line above the prompt are all updated. When the result can't be read, the run's log and its result bundle say how it went. In 0.9.3 the line saying such a task had ended never appeared, and nothing was recorded.
- The coverage of a branch's changed lines no longer counts the tests themselves, says once that a run never reached a module, as a filtered run often doesn't, rather than listing its lines as not run, and isn't given for a run that ran no tests.
- The project's pinned Xcode is named in a failure's notes only when the errors look like another SDK or toolchain's, such as a module another Swift compiled or an SDK it can't find, and at most once a session for each pin, never on a run that passed.
- After Claude edits a project's manifest and then undoes the edit, the next build or test runs instead of being held back for a generate the project no longer needs.
- An Xcode MCP call that fails with "Connection closed", as after the selected Xcode changes during a session, says that /mcp → Reconnect restarts it, and `xcrew doctor` checks that a new Xcode MCP bridge answers.
- Usual run times are kept per repository and never include a failed run's, so a build that fails early no longer makes the next one look slow, and two projects with a scheme of the same name no longer share times. Old, stale and empty entries are cleared when a session starts, and `/xcrew history` shows failed runs apart.
- What Claude reads of the tests a branch can break (`xcrew affected`) gives their number first, grouped into unit and UI tests. A long list names a few of each and counts the rest, and gives the `-only-testing` arguments only for a short one.
- `/xcrew setup` opens a form in a pane. You pick the container, the app, UI-test and unit-test schemes, the bundle ID, the simulators and the debugger backend, then write the config. Each scheme says what it builds and tests, only installed simulators are offered, and one with two displays is marked. A config xcrew didn't write is replaced only through its own button, keeping a backup. After a write, Claude is told once that MobileBuildMCP reads the new config when Claude Code next starts. `/xcrew:setup` still sets xcrew up where the form can't be drawn.
- `xcrew setup --worktree` gives the worktree simulators of its own, named `xcrew · <project> · <worktree>`: a clone of the main checkout's while it's shut down, with its apps and data, else one made fresh on its device and runtime, and says which; `--fresh-simulator` makes a fresh one in place of a clone, and `--no-simulator` shares the main checkout's.
- A CI workflow that chooses its Xcode from `.xcode-version` now counts as CI using the pinned Xcode, so `xcrew xcode` and the doctor name it instead of saying CI names none.
- `xcrew why`, and a failed build's notes, now recognise a build database another build still holds (`database is locked`) and name the `xcodebuild` left running, with its pid and how to stop it, instead of blaming the code.
- `xcrew doctor` names an `xcodebuild` still building the project after what started it exited, such as a call stopped before its session ended, which holds the build folder so the next build fails, with its pid and how to stop it. One MobileBuildMCP still runs in a live session, from a stopped call or one moved to the background, shows in the full doctor.
- With Xcode 27 and no older Xcode beside it, Claude learns at the start that simulators show in DeviceHub, which has replaced Simulator.app, so it opens the right app.
- A test run's failures, and `xcrew why`, no longer count the coverage runtime's failure to write `default.profraw`, which isn't why a run fails.
- `xcrew doctor` says the headless Xcode MCP is enabled when no Xcode window is open, instead of only "Xcode isn't open".
- `xcrew doctor --problems` names the warnings it keeps off the prompt, such as the pinned Xcode's, so its "No problems." no longer contradicts the full doctor.
- A failed MobileBuildMCP screenshot of a simulator with two displays, and an LLDB command the default debugger backend refuses, now come with the way around: `xcrun simctl io <udid> screenshot --display=<id>`, and `xcrew setup --debugger-backend lldb-cli`, which setup keeps on later runs.
- `xcrew affected`, and Claude's `affected` tool, name the schemes that test only the targets a change can break, such as a module's own scheme, each with the targets it tests and any target none of them tests, so a test can use a module's scheme instead of `-only-testing:` on one that tests every module.
- `xcrew setup --choices` gives, as JSON, what setup can offer: the containers, each shared scheme with what it builds and tests, the installed simulators with any that has two displays marked, the starting picks, and whose the config is. It writes nothing.
- After a MobileBuildMCP build or test whose log holds 10 or more Swift concurrency diagnostics, Claude reads one note: how many, in how many modules, and that `xcrew concurrency` lists them. It's given once per scheme a session, and again when the count rises a quarter above the highest given.
- `xcrew concurrency` counts a build's Swift concurrency diagnostics by the compiler's own group and by module, from its log, with each group's title from your Xcode's docs, how many are in lines your branch changed, and how many carry no group.
- `xcrew graph` shows a project's modules as its projects declare them, what each depends on, and where each import of one lands: a direct dependency, one reached only through others, one it doesn't depend on, or one that depends on it. `--owner <file>` names the targets that build a file.
- xcrew's notes to Claude now state facts and offer tools instead of prescribing steps. It still routes work across its servers and guards your work: DerivedData isn't deleted unless you ask, and a snapshot's reference is re-recorded only with your agreement.
- The red-to-green ledger turns a test green once any run that ran it passes, a run of its class or target after it failed under its own method filter included, and a test that failed every repeated run reads "failed every run" rather than "failed some of its repeated runs".
- A pull request can carry the branch's evidence: the tests it took from red to green, with their failing run's images, the tests still red, the coverage and warnings of the lines it changed, and usual run times, as a block to paste. When Claude writes a pull request's body it can offer you the block, and adds it only if you want it; the images come after it, for you to attach or leave out, and no local path goes into the pull request. `/xcrew evidence` shows the same.
- In a git worktree, such as one Claude Code's `--worktree` makes, `xcrew setup --worktree` writes the worktree's MobileBuildMCP config from the main checkout's, leaving out a DerivedData folder the main checkout uses so the two don't build into one. The session briefing and `xcrew doctor` name it in a worktree that has no config yet.
- A failed UI test's notes now point Claude to `look`, so it sees the screen at the failure before changing the test or the view.
- A test that fails under some test-plan configurations or devices and passes under others now says where it passed, and the session briefing names each scheme whose test plan runs under several configurations, so Claude treats such a failure as that configuration's.
- `xcrew space` shows what MobileBuildMCP and Xcode keep on your Mac: this project's MobileBuildMCP storage and any a project that's gone left behind, Xcode's DerivedData by the workspace it served, simulator runtimes and devices, and the installed Xcodes, each with the command that would reclaim it. It deletes nothing, and never offers the selected or pinned Xcode or your archives.

## 0.10.0 — 2026-10-30

- When a UI test fails because an element wasn't found, `look` also lists the elements that were on screen, by type, label and identifier, so Claude can tell a renamed element from a missing one.
- When a UI test fails, Claude can look at the screen at the failure: the `look` tool gives, for each test-plan configuration and device it failed on, the last steps before it and a picture of the screen, the last frame of the run's recording. `xcrew look` prints the same.
- When a snapshot test fails, Claude sees its images: the reference, the failing render and their difference, listed under the test and in the failures pane. Claude looks at them before changing the code or the reference, and re-records a reference only when you agree the new render is right.

## 0.9.3 — 2026-10-30

- The project card reaches Claude on every plan. Claude Code passes over a plugin's prompt hooks on Team organisations, so the card that used to ride on the first message now comes with the session's start, and after a `/clear` or a compaction, and says how old its notes are.
- A build or test that Claude moves to the background no longer shows as passed the moment it moves: the line above the prompt says it has no result yet, nothing is timed or recorded, and when the task ends the line says so and that its result is in the conversation.
- A pinned Xcode that isn't the one building no longer shows in the line above the prompt. `xcrew doctor` still lists it, and when a build or test fails, its notes say which Xcode built and which the project pins, as a possible cause.

## 0.9.2 — 2026-10-30

- In a config of your own that still enables MobileBuildMCP's `xcode-ide` group, Xcode MCP tools it forwards get Xcrew's checks too. In a generated project you're asked before `XcodeWrite`, and a build after a manifest edit is held back for the generate. Tools it proxies are timed and named in the status line as the Xcode MCP's own.

## 0.9.1 — 2026-10-30

- The doctor no longer reports an error when the project's pinned Xcode isn't installed: it warns, naming both versions, and says when the build may fail (another major version, or a newer pin). It no longer reports an error for headless Xcode MCP on a Mac whose Xcodes all predate Xcode 27, and when Xcode 27 is installed but an older one is selected, it names the `xcode-select` command that turns headless Xcode MCP on. Its fix for a missing Xcode names `xcodes install` only when `xcodes` is installed, and Apple's download page otherwise.
- When Claude builds or tests a project MobileBuildMCP has no scheme for yet, it's told to offer `/xcrew:setup`, once per conversation. The conversation's opening note says so too, now also when MobileBuildMCP saved a config of its own without one. The README now says that with mcs you run `/xcrew:setup` once after `mcs sync`.
- When setup replaces a config, the session defaults it doesn't set itself, such as `derivedDataPath` or `env`, go into each profile instead of being dropped, and setup says which. A simulator that isn't installed is still written, and setup and `xcrew doctor` name the installed iPhones and the exact `xcrun simctl create` command when an installed runtime supports it. `/xcrew:setup` checks each simulator before passing it, and asks whether to create a missing one or use an installed one. The README now says Xcode 26.3 or later, and that Xcode 27 also runs the Xcode MCP with Xcode closed.
- Setup writes the config's workspace, project and DerivedData paths from the project root (`./App.xcworkspace`), so a config copied into another worktree builds that worktree, not the original checkout. Configs with absolute paths keep working.
- MobileBuildMCP no longer offers its own route to the Xcode MCP (`xcode-ide`), which let Claude call `XcodeWrite` without Xcrew asking you first in a generated project. Claude can now set the simulator's status bar through MobileBuildMCP. `xcrew doctor` says when a config still has the old tool groups, and `/xcrew:setup` rewrites it.

## 0.9.0 — 2026-10-30

- When Claude runs the whole test suite again and again in a short while, the run that makes it a habit tells Claude to run only the tests the change can break, and the whole suite again before the pull request. A fast suite never hears it.
- A project that pins its Xcode in `.xcode-version` builds and tests with it through MobileBuildMCP, even when another is selected. `xcrew doctor` says when the pin can't apply, when CI uses another Xcode, and when the Xcode that's open isn't the one builds use, which would put two toolchains in one session. `/xcrew xcode` shows which is which, in the chat.
- When a build fails because of the Mac rather than the code, such as a corrupt module cache or a simulator that's gone, Claude is told so, with the fix to run, instead of editing code that was never wrong. `xcrew why` says the same of an earlier failure. A failure the Mac doesn't explain gets no such note.
- Installs are about 3 MB smaller: the README's images no longer come with the plugin.
- With mcs, the plugin now loads straight from the pack's checkout instead of a second copy from the marketplace, so it always matches the pack. It shows as `xcrew@mcs-xcrew` and starts with empty plugin data. Requires mcs 2026.10.30. Add the pack with `mcs pack add breferrari/xcrew --ref stable`, or `ref: stable` in `mcs.yaml`, to get releases rather than unreleased code, and `xcrew doctor` now says `mcs update` for an mcs install.

## 0.8.9 — 2026-10-30

- When a test fails for no reason the change explains, Claude runs it alone several times, and Xcrew says whether it's flaky (failed some runs) or a real failure (failed every run). A flaky test stays red, marked flaky, in the red-to-green record and on the project card, until a repeated run passes it every time.
- Of a build's warnings, Claude is told which are in lines your branch changed, so it fixes its own and leaves the rest. Warnings elsewhere are counted, never claimed new or old.
- After a test run with coverage on, Claude is told which of the lines your branch changed that run ran, and which it didn't. The routing rules have Claude turn coverage on for a run before a pull request.

## 0.8.8 — 2026-10-30

- Before Claude edits a file your Tuist or XcodeGen project generates (inside the `.xcodeproj` or `.xcworkspace`, or Tuist's `Derived` folder), Xcrew asks you, since the next generate overwrites the edit. Say no, and Claude is pointed at the manifest to edit instead and the generate command. `XcodeWrite` in a generated project now asks the same way instead of being refused outright.
- Each conversation starts with a short card in Claude's context: how long builds and test runs usually take in this folder, the tests still failing on the branch, and, when a full test run is slow, the selections run before. It's built from what Xcrew already recorded, sent once per conversation, and kept to a few lines.
- `xcrew affected` lists the tests your branch's changes can break, from the targets the project says own the changed files and every target that depends on them, across the projects of a modular app. Claude asks it, through a tool of the mod's, before running the whole suite, and runs only those tests. When a change touches something it can't read, such as the project file, a scheme, an `.xcconfig`, a package or a manifest, it says to run everything and names the file.

## 0.8.7 — 2026-10-30

- In a Tuist or XcodeGen project, after Claude edits a manifest, the next build or test, or a run that builds first, is refused once with the command that regenerates the project, such as `tuist generate --no-open`, so it doesn't build the project as it was. With several Tuist apps in one repository, each app edited needs its own generate, and the refusal names every one still to run. A generate that succeeds lets builds run again; if you generated in your own terminal, the next attempt goes through. After a change to `Tuist/Package.swift`, the command runs `tuist install` first. A spec your `project.yml` includes counts as a manifest too. A source file that only shares a manifest's name, like a `Project.swift` model, doesn't count.
- Claude can list the tests it saw fail and then pass on the branch, each with the run where it failed and the run that passed it, ready for a pull request's test plan. `/xcrew ledger` shows you the same. The record lasts across sessions, per branch, and is dropped once no test run has touched it for weeks.

## 0.8.6 — 2026-10-29

- When MobileBuildMCP is missing or out of date, the session briefing has Claude build and test through the Xcode MCP and tell you once what that loses (coverage, simulator control, UI automation, LLDB), instead of stopping at "install it". It asks before switching your open Xcode to another scheme.

## 0.8.5 — 2026-10-29

- The line above the prompt follows only its own run, so two sessions building in one checkout, or in two checkouts of folders with the same name, no longer show each other's progress.
- `xcrew doctor` finds the in-place macro copy phase older Tuist generated in a project saved in Xcode 27.2's JSON format too, not only in `project.pbxproj`, and warns as it does there.
- Installs now follow a `stable` branch that each release moves forward, in place of a tag the marketplace names, so a release reaches `claude plugin update` the moment it is published.

## 0.8.4 — 2026-10-29

- A build or test call's row in the transcript shows its outcome, as the line above the prompt does: `✓ test_sim · 1:12 · 959 passed`, or the first failures and how many more. ctrl+o shows the result Claude read, which is unchanged.
- The line above the prompt asks you to restart Claude Code whenever setup or `mcs sync` wrote the config after MobileBuildMCP started, and stops once you have. `xcrew doctor` has the check: `mobilebuildmcp/config-loaded`. A hand edit still needs a restart by hand. Setup no longer rewrites a config that hasn't changed.
- A compiler warning that fires in several places reaches Claude once, with how many times and every file and line, in place of one copy of the message per place. Warnings that differ are left as MobileBuildMCP wrote them.
- The session briefing tells Claude to leave DerivedData alone unless you ask, and to report a build that looks corrupted instead. It also says to build, test and drive simulators through MobileBuildMCP rather than `xcodebuild` or `simctl` in Bash, which stays for your own build scripts and what no tool covers, such as archiving.
- The session briefing names the simulators booted now, when any are, so Claude reuses one rather than booting another.
- A large test result that Claude Code saved to a file is still read back and shortened if a later Claude Code words its notice differently: xcrew finds the file by its path rather than the notice's sentence.
- `/xcrew history` drops a line no run has updated for two weeks, so lines in a format an older version wrote stop showing beside today's, and month-old runs no longer count toward a build's usual time.
- The notification after a long failing run carries its outcome alone, without the `/xcrew failures` pointer, which can't be typed from a notification. The line above the prompt, and the toast where that line can't draw, still end with it.
- `xcrew doctor`'s exit status no longer depends on which check comes first: 1 when one failed, 2 when one warned, 3 only when every check skipped, else 0. A skipped first check used to make a clean run exit 3.

## 0.8.3 — 2026-10-29

- `/xcrew:setup` now asks which folder to use when two qualify, or tells you to generate a Tuist project first, and no longer mistakes a doctor warning for a failed setup.
- `xcrew setup` picks a standard iPhone simulator again. A device with its own runtime, such as the iPhone Duo with Xcode 27.2, no longer looks newer than the rest, and a simulator with two displays is never the default, since screenshots fail on it. `xcrew doctor` warns when your config already names one.
- After `/xcrew:setup` writes the config, the line above the prompt asks you to restart Claude Code.
- The line above the prompt keeps itself current. A passed run leaves after 3 minutes, a failed one when you look at it or after 30. A failing check stays until it's fixed, however you fix it; a warning shows for two minutes.
- A fix text mentions mcs only in a project set up through mcs.

## 0.8.2 — 2026-10-29

- `xcrew setup` writes only profiles that have a scheme, finds your unit-test scheme itself, and writes each profile's simulator ID, so `screenshot` works after a profile switch. `xcrew doctor` flags configs from 0.8.1 and earlier: rerun `/xcrew:setup`.
- A fresh install from the marketplace now gets the tagged release, not the newest code on main under the last release's version. `xcrew doctor` also shows the commit beside the version when Xcrew runs from a git checkout.
- `xcrew doctor`'s fix for a missing MobileBuildMCP config now says "the mcs CLI": on a Mac with Mono, a bare `mcs` is Mono's C# compiler.
- The first run now says building Xcrew's CLI takes 10 to 20 seconds, instead of "about 10 s".

## 0.8.1 — 2026-10-29

- Xcrew builds with Swift 6.2 (Xcode 26.0) again, the oldest toolchain it supports. Since 0.7.2, one line in how it reads a test run needed Swift 6.3 to compile, so the first build failed on Xcode 26.0 and 26.0.1.
- The line above the prompt is easier to read: the time, the time left, the phase, the result and the scheme and simulator are in your theme's text colour, and only the separators between them stay faint. On a finished run, the scheme and simulator come last, as they do while it runs, so a narrow terminal cuts them before the outcome.
- A script that runs `xcrew hook` or `xcrew report` and leaves standard input open no longer waits forever: xcrew stops reading once two seconds pass with nothing new, says so on stderr, and goes on. A file passed on standard input is read at once. Claude Code closes the input, so it was never affected.

## 0.8.0 — 2026-10-29

- **Apps a folder or two below the root.** In a git repository, an app kept in `ios/`, `apps/ios/` or `apps/MyApp.iOS/` counts as an Apple-platform project: Claude gets the session briefing and the line above the prompt shows the doctor's problems. `xcrew setup` without `--container` finds its workspace or project there too. In a generated project it takes the one beside the manifests and says `generate it first` when that isn't there yet. When two folders hold projects equally near (`apps/ios/`, `apps/macos/`), it names them and asks for `--container`.
- **Generated projects, told apart more carefully.** A source file named `Project.swift` or `Workspace.swift` below the root no longer marks a classic project as Tuist-generated, so Claude can edit its project files again. A Tuist app found by its git root alone is still guarded. The doctor finds Tuist's old macro copy phase in every Tuist app in the project, not only at the root.
- **The project search** finds a project opened through a symlink again, and never walks your home folder, however its path is spelled and wherever it sits.
- **`xcrew doctor` outside an Apple-platform project** skips the two project checks (`not an Apple project`) instead of failing them and suggesting setup.
- **`xcrew <command> --help`** prints that command's usage. An option or word a command doesn't take is refused with exit 64 instead of being ignored: `xcrew doctor --help`, `-l` or `problems` used to run every check.
- **Build, test and run tools are recognised by whole words in their names.** A tool with *latest* in its name is no longer timed as a test run, while `RunTargetTests`, `RunUITests`, `swift_package_build` and `launch_mac_app` are timed. Switching the test plan (`XcodeSwitchTestPlan`) and tools that only read, such as `build_settings`, aren't timed.
- **A build or test call that fails beneath Xcrew**, such as one that's interrupted, no longer leaves the line above the prompt or the status line counting.
- **A command Xcrew runs that exits while a background process it started keeps running** no longer holds Xcrew up until that process ends: Xcrew gives the command's output a second to arrive, then goes on.
- **The README's new *Privacy* section** lists everything Xcrew reads, runs, changes and sends, and the plugin's privacy link opens it.
- **The Xcode MCP and MobileBuildMCP** now start from small scripts in the plugin, in `libexec/`. What they do doesn't change.

## 0.7.3 — 2026-10-29

- After a failing build or test run, the line above the prompt ends with `/xcrew failures`, which opens the pane listing each failure.

## 0.7.2 — 2026-10-29

- The mod runs the CLI's build directly, about 5 ms a call instead of about 35 ms through `bin/xcrew`, which matters most for the band's once-a-second phase. `bin/xcrew` itself no longer hashes the sources on every call: it keeps the key in its cache and works it out again only when a source changes.
- A call you deny at the permission prompt leaves no trace: no time in the usual-duration history, no outcome line, no notification.
- A build killed outright no longer leaves a lock that holds up every Xcrew call for ten minutes.
- A Tuist project with a root `Tuist.swift`, or with its manifests a folder or two below the root (`ios/`), counts as generated: the `XcodeWrite` guard and the doctor's copy-phase check both find it.
- Any MobileBuildMCP `session_` answer and any Xcode MCP switch answer updates the scheme and simulator the band shows, such as `session_clear_defaults`.
- The band follows its own project's log, not another project whose name starts the same (`App` and `App-Legacy`).
- On a crash-heavy run, Xcrew looks up at most four tests at once, so a busy Mac doesn't time its lookups out.
- The band's phase stays fast when a log ends in a long run of warnings.
- The band's phase stays cheap on a clean build: it reads the end of the log, not all of it. A 45 MB log took 1.4 s a second to read; now it takes 0.07 s.
- Session start is faster outside Tuist projects: the doctor looks for Tuist's old macro copy phase only where Tuist generated the project. It took about 0.7 s in a large project.
- The installed plugin and a development checkout no longer rebuild each other's CLI in turn: a cached build is removed after two weeks unused, not whenever another version builds. Two first runs at once now build once.
- `xcrew doctor --problems` lists failures before warnings.
- With mcs, the techpack no longer runs its own check for a newer Xcrew: `mcs check-updates` already reports pack updates, and `mcs update` installs them. `xcrew doctor` keeps the check for plugin installs.
- The note about a run's expected failures names the tests, five at most.
- A crashed test whose run attached no crash log says so, and how to get one, so Claude knows why there are no frames.
- `xcrew doctor --problems` prints `No problems.` when there are none, rather than nothing.

## 0.7.1 — 2026-10-29

- A test run that fails to compile counts each compile error once, as a build does: the compiler's caret line was counted as a second error.
- Installing or syncing Xcrew with mcs works again: 0.7.0's new description made `techpack.yaml` invalid YAML, so mcs couldn't load the pack.

## 0.7.0 — 2026-10-29

- The macro-plugin repair is gone: the mod's retry, the hooks after a failed Xcode MCP build, `/xcrew repair`, `xcrew repair-macros` and the doctor's `xcode-mcp/macro-plugins` check. Finding a dead plugin meant launching every macro plugin in DerivedData, and the cause, the in-place copy phase Tuist generated before 4.203, is gone from current Tuist. `xcrew doctor` still names projects generated with that phase, with the fix: upgrade Tuist and regenerate. `XCREW_MACRO_PLUGINS` and `XCREW_DERIVED_DATA` no longer do anything.
- The README describes Xcrew as it is now, leading with what it changes: one setup for the three servers, builds and tests you can watch, and test results Claude can act on, for any Apple-platform project. Drawn mockups show the line above the prompt, a compact test result, the failures pane and how the pieces fit together.
- The plugin's description, in the plugin list and on the techpack listing, now reads "Your Xcode crew inside Claude Code: three MCP servers working as one, with live build progress and test reports Claude can act on."

## 0.6.10 — 2026-10-28

- A skipped test reaches Claude with its reason even when MobileBuildMCP leaves it out of its Test Results list, which it can in a run that also crashes or records expected failures: the skipped tests and their reasons now come from the result bundle's test list, in one `xcresulttool` call rather than one per test.

## 0.6.9 — 2026-10-28

- `xcrew doctor` (and `/xcrew doctor`) checks whether a newer Xcrew is out, against the latest GitHub release, and says how to update or turn on auto-update. It's the only check that reaches the network: the session-start look for problems leaves it out, and it skips rather than fails when GitHub can't be reached.
- The README says how to turn on auto-update, which Claude Code leaves off for third-party marketplaces.

## 0.6.8 — 2026-10-28

- A skipped test's reason reaches Claude in a long failing run too: 0.6.6 and 0.6.7 looked it up, then dropped it when they compacted the Test Results list.

## 0.6.7 — 2026-10-28

- A MobileBuildMCP test run with expected failures (`XCTExpectFailure`) tells Claude how many ran, and the true total: MobileBuildMCP's counts leave them out.

## 0.6.6 — 2026-10-28

- A crashed test reaches Claude with the crash's exception and the top frames of the thread that crashed, from the crash log its result bundle attaches.
- A skipped test reaches Claude with why it was skipped, from its result bundle.
- A compile error is counted once: MobileBuildMCP also listed the compiler's caret line as an error of its own.
- A compacted failing run lists its failures once, under Test Failures, rather than again under Test Results, where the parallel runners' log can miss some; and the note for a left-out per-test list no longer gives a count that can disagree with the summary's.

## 0.6.5 — 2026-10-28

- A compacted failing run keeps its skipped tests' lines (`⏭️`) beside the failing ones; 0.6.2 to 0.6.4 left them out with the passing tests, so a skipped test showed only in the count.

## 0.6.4 — 2026-10-28

- The plugin list shows the plugin as `xcrew`, its id, like the `xcode` server: the capitalised Xcrew stays for the README and the techpack card.

## 0.6.3 — 2026-10-28

- A failing MobileBuildMCP test run gives each failure its file and line, in the result Claude gets and in the failure pane. Run on parallel simulator clones, xcodebuild logs failures without them, so the mod reads them from the run's result bundle with `xcresulttool`, one quick lookup per failing test.

## 0.6.2 — 2026-10-28

- A failing MobileBuildMCP test run reaches Claude with its failures and summary, its passing tests counted instead of listed (with `showTestTiming` on, a 959-test run listed every one). A list Claude Code already cut in the middle loses its marker and fragments.
- A test run that ran no tests shows `✗ … no tests ran` instead of a green `✓`, and Claude is told an `-only-testing` filter probably matched nothing: MobileBuildMCP reports such a run as SUCCEEDED.
- The doctor's `macro-copy-phase` warning names the installed Tuist and says whether the fix is to upgrade it or only to regenerate the project.
- The hook spinners read `Preparing Xcode tooling` and `Checking Xcode macro plugins`, without an `xcrew:` prefix.

## 0.6.1 — 2026-10-28

- A large test result now does reach Claude as its summary: 0.6.0 replaced the result's text but kept the reference to Claude Code's own messages, which Claude Code then showed instead. The mod now answers with its own result.
- A MobileBuildMCP run's gauge starts when its log appears, so a pre-build hook's wait no longer shows a normal run as over its usual time. Until then the band says `preparing`.
- `/xcrew history` names a test selection run without a known scheme as `test_sim › AppTests`.

## 0.6.0 — 2026-10-28

- A MobileBuildMCP test result too large for the transcript reaches Claude as its summary, counts, failures and artifacts, with the per-test list left out and the saved file named for it: a 959-test run's 122 KB becomes about 2.5 KB, and Claude no longer needs a `jq` call to read it.

## 0.5.2 — 2026-10-28

- The failure pane clears only when the same tool, scheme and test selection passes, since another scheme's pass never re-ran those tests. Clearing also closes the pane, and `/xcrew close` closes it from the prompt: in Claude Code's default layout (`"tui": "default"`) its close mark can't be clicked; in the fullscreen layout it can.

## 0.5.1 — 2026-10-28

- Before a MobileBuildMCP run's log appears, the band says `preparing` rather than `waiting to start`: the server's own preparation, such as counting tests, happens there too, not only a pre-build hook or a permission prompt.
- The failure pane shows an `XCTFail` as the message it was given, without XCTest's `failed - ` in front.
- `/xcrew history` puts the numbers first, so a long scheme and test selection doesn't push them out of line.

## 0.5.0 — 2026-10-28

- `/xcrew failures` opens a pane listing every failing test and compile error of the last failing run, with its message and where it failed. A later passing run of the same tool clears it.
- When a session starts with something wrong (Xcode MCP not approved, MobileBuildMCP missing, a project still killing macro plugins), the band says so until the first run, with `(+N more)` and where to look. `xcrew doctor --problems` prints only what failed or warned, and nothing outside an Apple-platform project.
- Usual durations, the slow-run note and test totals are kept per scheme and test selection, so testing one module isn't measured against the whole app. Durations recorded before are kept under the tool alone.
- While a build or test run goes, the band draws a gauge of its time against the tool's usual duration, with the time left: `build_sim · 0:21 ━━━━╸─── ~0:15 left`. Past the usual time it turns to the warning colour and counts how far over. It's an estimate: xcodebuild prints no build percentage a mod can read. The first run of a tool shows its time alone.

## 0.4.1 — 2026-10-28

- Until a MobileBuildMCP run's log appears, the band says `waiting to start`, so a pre-build hook or a permission prompt doesn't look like a stalled build. Only tools that have written a log before say it, so `clean` doesn't.
- The phase is shorter and comes before the target: `build_sim · 1:02 · compiling Utility · MyApp on iPhone 17`. The file being compiled is left out, so a narrow terminal cuts the target, which you already know, not the time or the phase.

## 0.4.0 — 2026-10-28

- While a MobileBuildMCP build or test run goes, the band says what it's doing, from the log it writes as it runs: `compiling Utility · Formatter.swift`, `linking Utility`, `testing 431 of 959` against the last run's total. Test results reach the log in batches, so the count moves in steps. The Xcode MCP writes no log to follow.
- Runs are timed by the duration the server reports, so a project's pre-build hook or a permission prompt no longer counts toward a build's time or its average.

## 0.3.0 — 2026-10-28

- The marketplace is named `breferrari`, so the plugin installs as `xcrew@breferrari` rather than `xcrew@xcrew`. An install from 0.2 or earlier is removed and installed again: `claude plugin uninstall xcrew@xcrew`, then `claude plugin install xcrew@breferrari` (the `marketplace add` command is unchanged).
- `/xcrew doctor`, `/xcrew repair` and `/xcrew history` now work: the reference skill, named like the plugin, took the `/xcrew` command, so Claude Code refused the mod's. It's `xcrew:reference` now, and out of the `/` menu.
- `/xcrew history` starts with a heading, so the name Claude Code puts before a command's output doesn't push the first row out of line.

## 0.2.0 — 2026-10-28

- Where the band draws (the terminal, Desktop), it carries a run's outcome alone; the toast that repeated it now shows only where no band draws.
- A result too large for the transcript, which Claude Code saves to a file, is read back from that file, so its outcome still carries its detail (a large project's test run lost its count).
- The status line and band name the scheme after `XcodeSwitchScheme` too, which reports it as `activeSchemeName`.
- A run far slower than usual says so: `(2× its usual 1:50)` once there are five earlier runs, at 1.5× the average or more.
- After a macro-plugin repair, the toast names the projects that will keep killing plugins until Tuist 4.203 or later regenerates them.
- `/xcrew doctor`, `/xcrew repair` and `/xcrew history`, answered by the mod without a turn for Claude.
- In a generated project, `XcodeWrite`'s description says it's refused there, so Claude reaches for Write first.
- The mod type-checks under `strict` (`scripts/typecheck.sh`), on any machine's set of MCP servers.

## 0.1.0 — 2026-10-28

- Plugin with MobileBuildMCP, the Xcode MCP and Sosumi; a session briefing with the routing rules.
- Mod: macro-plugin repair with retry, build and test timing, the `XcodeWrite` guard.
- Swift CLI: `setup`, `doctor`, `repair-macros`, `xcode-skills`, and the hook entry points.
- mcs techpack installing the plugin, MobileBuildMCP and the per-project setup.
- Runs show in colour on a line above the prompt, live and then with their outcome for a few minutes; the plain status line stays as the fallback where that line can't draw.
- The status line names the scheme and simulator a build or test run uses.
- A build or test run of a minute or more also sends its result as a notification.
- The build and test toast says what failed: the first compile error with its file and line, or how many tests failed and the first one. Failed Xcode MCP builds and test runs now count as failures; the server reports them as normal results.
- The doctor names projects still generated with Tuist's pre-4.203 in-place macro copy phase, and the repair message gives that cause and its fix.
- The macro-plugin repair hook runs only when a build fails with the plugin-kill message, and the doctor skips projects with no macro plugins.
- The `XcodeWrite` guard applies only to generated projects; `xcode-skills` keeps a project's own skills of the same name unless `--force`; setup keeps a managed config that was edited by hand; the README installs per project.
- Macro-plugin repair also covers the indexer's build and Swift packages opened directly, and labels the indexer's copies.
- Setup keeps `.mobilebuildmcp/` out of git; the doctor warns when the config points at a workspace that moved; `xcrew --version`; the CLI cache keeps only the current build.
