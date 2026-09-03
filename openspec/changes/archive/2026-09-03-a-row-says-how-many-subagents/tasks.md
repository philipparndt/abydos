## 1. The count

- [x] 1.1 `ClaudeHook.Event` reads `tool_name`; `ClaudeHookRunner.announce` sends it as `tool`.
- [x] 1.2 `RunningSessions.Session.subagents`, moved by `note`: up on a spawning `PreToolUse`, down on `SubagentStop`, floored at nought, reset by a finished turn.
- [x] 1.3 Tests for each scenario, against the payload shape the hook posts.

## 2. The row

- [x] 2.1 The trailing text says `n subagents` when there are any and nothing when there are none.
- [x] 2.2 Driven: a session with two out reads them in the report; one with none says nothing.

## 3. Finishing

- [x] 3.1 Say it in the release notes.
- [x] 3.2 `make test` and `make warnings`, both clean, both by their exit codes
  — 4023 tests in 512 suites passed in 57.6 s at load 13 on 2026-09-03, with
  the suite's two standing known issues, and both runs returned 0. The six
  attempts that failed the evening before were load-bound give-up bounds, not
  this change.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `running-sessions` delta in
this change is what it makes true.
