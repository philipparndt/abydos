## 1. Name it

- [ ] 1.1 Reproduce the overlap in a driven run, opening the backlog by the routes a person uses — a fresh window, a tab switch, and a zoom while it is showing.
- [ ] 1.2 Write the ordering that causes it into the design. If it cannot be reproduced, say that, and say what was ruled out.

## 2. Fix it

- [ ] 2.1 Make the pane's placement independent of the order it and the strip are sized in.
- [ ] 2.2 Check the other panes for the same ordering, and record whether the fault was the panel's or the backlog's.

## 3. Finishing

- [ ] 3.1 Driven capture of the pane's header position, so the claim is a measurement rather than a screenshot somebody looked at.
- [ ] 3.2 `make test` and `make warnings`, both clean, both by their exit codes.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`.
