## 1. Name it

- [x] 1.1 Reproduce the overlap in a driven run, opening the backlog by the routes a person uses — a fresh window, a tab switch, and a zoom while it is showing.
- [x] 1.2 Write the ordering that causes it into the design. If it cannot be reproduced, say that, and say what was ruled out.

## 2. Fix it

- [x] 2.1 Make the pane's placement independent of the order it and the strip are sized in.
- [x] 2.2 Check the other panes for the same ordering, and record whether the fault was the panel's or the backlog's.

## 3. Finishing

- [x] 3.1 Driven capture of the pane's header position, so the claim is a measurement rather than a screenshot somebody looked at. `--backlog-geometry` on 2026-09-03: header 30–64 at 1.0, 45–96 while presenting at 1.5, 30–64 after; 82–116 with the panel maximised; unchanged through a theme walk. Zero points below the strip every time.
- [x] 3.2 `make test` and `make warnings`, both clean, both by their exit codes. Green here on 2026-09-03: 4005 tests in 511 suites, exit 0, load 23.3 over 14 cores; `make warnings` exit 0.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`.
