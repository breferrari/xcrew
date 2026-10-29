# Live check

The mod's tests run against captured outputs. This checks the real thing: a release candidate in a real iOS project, against MobileBuildMCP and Xcode as they are today. Run it before a release that changes what Claude sees from a build or a test, and whenever a new MobileBuildMCP or Xcode lands.

Run the candidate from your clone with `claude --plugin-dir <your clone>` in the project, since `claude plugin update` installs the last tagged release, never `main`. Paste the prompt below into a fresh session. Fill in the two placeholders: a scheme, and a test target of it with a few hundred tests or more, so the result is long enough to be compacted. The session reports what it received; the last section is for you, since only your terminal shows it.

## The prompt

```
Check Xcrew in this project. Report each item as pass or fail, with the evidence: paste what you received from the tool, not a paraphrase. The probe file below is temporary: delete it at the end and confirm `git status` is clean.

Setup: `claude plugin list` shows xcrew@inline, from your clone, at the version under test. Use MobileBuildMCP with the scheme <SCHEME> and its test target <TARGET>.

A. A failing run. Add a test file to <TARGET>, an XCTestCase `XcrewProbeTests` with:
   - `test_fails`: `XCTAssertEqual(1, 2)`
   - `test_skips`: `throw XCTSkip("xcrew probe skip reason")`
   - `test_crashes`: `let a: [Int] = []; _ = a[1]`
   - `test_expectsFailure`: `XCTExpectFailure("known"); XCTFail("expected")`
   Run the whole target, not just this class. Check that:
   1. The failure appears once, under Test Failures, with an absolute `file:line` in the probe file.
   2. The crash shows its exception and up to 5 frames, as `image  symbol`.
   3. Test Results has `⏭️ XcrewProbeTests/test_skips()` followed by `skipped: xcrew probe skip reason`.
   4. A note beside the result names the expected failures and gives the true total of tests that ran.
   5. Passing tests are left out with a note, and the counts match the summary line. Give the result's size in characters.

B. A compile error. Add `let x: Int = "a"` to `test_fails` and build for testing (`build_sim` with `buildForTesting: true`; a plain build skips the test target). The result says `Errors (1)` and lists the error once.

C. A clean run. Delete the probe file and run the target again. It passes, and the per-test list is left out with a note.

D. Doctor. Find the plugin's `bin/xcrew` (under ~/.claude/plugins/cache) and run:
   1. `xcrew doctor`: every check, including `xcrew/up-to-date`.
   2. `xcrew doctor --problems`: only failures and warnings, or `No problems.`, with no `xcrew/up-to-date` line.
   3. `HTTPS_PROXY=http://10.255.255.1:9 xcrew doctor`: `xcrew/up-to-date` is skipped with "<version>: couldn't reach GitHub to compare", within about 5 seconds.

E. The CLI's shim, with the same `bin/xcrew`:
   1. `bin/xcrew --binary-path` prints the path of a built `xcrew`, and that path's `--version` is the version under test.
   2. Run `bin/xcrew --version` twice and time the second: well under 100 ms, since the shim keeps its key and doesn't hash the sources again.
   3. `bin/xcrew report --server other --kind build </dev/null` exits 64, and its message names `MobileBuildMCP or xcode`.

F. Profiles. Switch MobileBuildMCP's session profile with its `session_` tools, to another scheme or simulator and back, and report each answer.

End with `git status` (clean) and a short list of anything that looked wrong or unclear.
```

## What only you can see

While the session runs A to C:

- The band above the prompt shows the tool, the elapsed time, the gauge against the usual duration, and the phase: `preparing`, `compiling <target>`, `testing X of N`.
- The status line shows the estimate.
- After A, the band ends with `/xcrew failures`, which opens the pane with the probe's failures; `/xcrew close` closes it.
- After C, `/xcrew history` lists the target's runs, and `/xcrew doctor` matches D1.
- During F, the band follows each switch: the next run shows the scheme and simulator the profile names.
- Deny one build at the permission prompt. It leaves no `/xcrew history` entry and no outcome line.
