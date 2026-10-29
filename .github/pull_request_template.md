<!--
Title: one clause, imperative, no "because". Start it with its kind: fix: for a defect or feat: for a new feature that users get, otherwise ci:, docs:, test: or chore:.
-->

## Summary

<!-- What this changes and why. Link the issue: closes #123. -->

## Test plan

<!-- The checks you ran and their result, with numbers. Name the tests you saw fail before the change. State failures plainly. -->

- [ ] `swift test` passes
- [ ] `claude plugin test .` passes (if the mod changed)
- [ ] `scripts/typecheck.sh` is clean (if the mod changed)

## Release note

<!-- One line for someone who has never opened this repository, saying what changed for them. It also goes under "## Unreleased" in CHANGELOG.md, placed by what a reader notices first. Write "none" for internal work: CI, tests, docs. -->
