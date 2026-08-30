## 1. Force the recompile, and mean it

- [x] 1.1 Replace the `rm -rf` of the non-existent swiftbuild path with a touch
      of this repository's `*.swift` under `Sources/` and `Tests/`. Verify with
      `bash -n` that the script still parses.
- [x] 1.2 Verify the gate now agrees with itself: three consecutive `make
      warnings` runs, the first on a wiped scratch path and the next two warm,
      each reporting the same two warnings and exiting 2. *(Done — before the
      change a warm run reported "No warnings" and exited 0 on this tree.)*
- [x] 1.3 Verify it is still not a cold build: **83 seconds under load 9.81 on
      sixteen cores**, against the script's own recorded claim of 67 seconds on a
      ten-core machine at `-j 4`. The load is beside the number because a number
      without one cannot be told from a regression.
- [x] 1.4 Say in the script what the touch costs — the next `make build` or `make
      test` recompiles this repository once — so the side effect is read where the
      line is, not discovered later.

## 2. What this change makes untrue

Nothing under `openspec/specs`. `make warnings` is a build tool rather than
behaviour of the app, and no capability describes it; `.openspec.yaml` carries
`skip_specs: true` for that reason.
