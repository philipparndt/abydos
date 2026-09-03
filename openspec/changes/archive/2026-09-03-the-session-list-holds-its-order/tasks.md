## 1. The order

- [x] 1.1 Order the groups after the first by name, then slug; drop the recency comparison.
- [x] 1.2 Order sessions within a group by tmux session, then window index, then the ones with no window; drop the recency comparison.
- [x] 1.3 End every comparison in the session's id, so a dictionary's walk order and an unstable sort cannot show.

## 2. Proving it

- [x] 2.1 Tests for the three ways it moved: a group that stayed put while a session in it spoke, two windowless rows that stayed put, and windows in tmux order with the windowless row last.
- [x] 2.2 A test that the whole list is unchanged by an event arriving — the same order before and after.

## 3. Finishing

- [x] 3.1 Say it in the release notes, beside the list.
- [x] 3.2 `make test` and `make warnings`, both clean, both by their exit codes. Green here on 2026-09-03: 4017 tests in 512 suites, exit 0, load 17.1 over 14 cores; `make warnings` exit 0.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `running-sessions` delta in
this change is what it makes true.
