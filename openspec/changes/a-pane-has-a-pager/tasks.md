## 1. The environment

- [x] 1.1 `PAGER` no longer set in `PseudoTerminal.mergedEnvironment`, with the expired reason carried into the requirement rather than deleted
- [x] 1.2 `PseudoTerminalEnvironmentTests`: nothing is set where `cat` was asserted; the "what is already set wins" test stands unchanged
- [x] 1.3 `TmuxConfig.forgetPagerInRunningServer()`, called at launch off the main thread: a running server's global `PAGER=cat` — and only that value — is unset

## 2. Proving it

- [x] 2.1 A driven run: `git log` in a pane over a repository with more history than a screen shows a pager, and `q` gives the prompt back — the one claim a dictionary test cannot make
- [x] 2.2 Nothing in the suite or in `Scripts/` depended on `PAGER=cat`: anything reading a long `git` output in a pane says `--no-pager` for itself

## 3. Before finishing

- [x] 3.1 `make test` clean, `make warnings` clean, machine load said if a bound flakes
- [x] 3.2 No spec is made untrue: the terminal delta adds beside the environment requirements already standing
