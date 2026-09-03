## 1. The hook

- [x] 1.1 Put `notificationType` on the payload `ClaudeHookRunner.announce` posts, beside the derived status.

## 2. The register

- [x] 2.1 In `RunningSessions.note`, leave a `done` record alone for an idle nudge or a `SubagentStop`, and report no move; add `disregards(_:)` for the watcher to ask first.
- [x] 2.2 Tests in `RunningSessionsTests` for each scenario in the spec, against the payload shape the hook posts.

## 3. The corner

- [x] 3.1 `ClaudeWatch.handle` asks the register before announcing, and drops the toast for an event it disregards.

## 4. Finishing

- [x] 4.1 Say it in the release notes, beside the pill.
- [x] 4.2 `make test` and `make warnings`, both clean, both by their exit codes. Green on the reporter's machine, 2026-09-02: 4004 tests in 511 suites passed after 81.4 s with 2 known issues, exit 0. Every run here the same afternoon was red on one load-bound give-up test at loads of 16 to 56 over 14 cores.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `running-sessions` delta in
this change is what it makes true.
