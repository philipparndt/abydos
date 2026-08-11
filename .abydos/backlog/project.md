# Abydos

A terminal-first IDE for AI and cloud development, on macOS. Native AppKit: no
web view, no Electron. The terminal is where the work happens — shells, tmux
windows, agents, a program running in a pod — and the editor, the debugger and
the cluster arrange themselves around it.

## How it is built and run

    make build      # the .app bundle (CONFIG=debug|release)
    make run        # build debug and launch it
    make dev        # build debug and run in the foreground, logs on the terminal
    make test       # the suite (FILTER=name, TEST_TIMEOUT=seconds)
    make warnings   # every warning in this repository's own code
    make install    # copy into /Applications

Swift Package Manager underneath; `make` exists because the app is a bundle and
`swift run` cannot make one. Xcode 16 or newer, macOS 14 or newer. `make help`
lists the rest.

**`make warnings` before finishing an item.** It is not part of `make build` on
purpose — nothing is `-warnings-as-errors` here, and a wall that stops work gets
turned off — so it is a verb somebody runs, and if nobody runs it the count goes
back up. An ordinary build cannot answer the question: it is incremental, and it
only reports the files it recompiled, so a warning is seen once by whoever
happens to be watching the tail of a build and then never again. 0465 is the
account of what that costs. About a minute, and it fails on warnings that are
ours while counting the vendored grammars' C apart, because that is upstream's.

Some suites need something running — Docker or Apple's `container`, a
Kubernetes context, a language server. Those are named `…LiveTests` and skip
themselves when what they need is missing. A skipped live test is not a pass;
if the work is in that area, get the thing installed and run it.

## How it is laid out

- `Sources/AbydosKit` — the engine: text storage, syntax, the project model,
  git, LSP, DAP, the run configurations, the backlog. **No view code**, so all
  of it can be tested without a window. New logic goes here by default.
- `Sources/AbydosApp` — the AppKit shell: window, navigator, editor views,
  the bottom panel and its panes. A library rather than the executable, so an
  Xcode app target can be built from the same sources.
- `Sources/AbydosMain` — four lines: make an application, give it the delegate,
  run it.
- `Sources/AbydosHook`, `Sources/AbydosBacklog` — small binaries of their own.
  Both exist because they run where the app cannot: the hook runs several times
  per tool call, and the backlog runs in a worktree over a terminal.
- `Tests/AbydosKitTests` — one suite per subject, swift-testing.

## What the code is like

Read three files before writing one. The house style is unusual and consistent,
and matching it matters more here than in most repositories.

- **Comments say why, not what.** A comment that restates the code is noise; a
  comment that says which of two designs was chosen and what went wrong with the
  other one is the reason the file is worth reading in a year. Most of the
  comments here are the second kind, several are a paragraph, and that is
  deliberate.
- **The failure that motivated the code is worth naming.** "Unstandardised, a
  project under `/tmp` matched none of its own worktrees and the chip that names
  the branch never appeared." Somebody paid for that sentence.
- **British spelling** (`colour`, `behaviour`), tabs for indentation, and
  sentences rather than abbreviations in prose.
- **A test is a claim somebody can check**, named as a sentence:
  `aWorktreeCanFindTheCheckoutItWasMadeFrom`. Tests use `swift-testing`
  (`@Test`, `#expect`), not XCTest.
- **Cost is a design constraint.** This is an editor: things that run per frame,
  per keystroke or per row of a table are written knowing it, and where
  something is deliberately cheap the comment says so.

## What not to do here

- **Do not add a dependency** without a reason that survives being written down.
  The grammars are vendored on purpose; see `Package.swift`.
- **Do not put view code in AbydosKit.** The line is what makes the engine
  testable, and it has been held so far.
- **Do not renumber the backlog.** Commit messages cite those numbers.
- **Do not rewrite a completed item.** What it says is what somebody knew at the
  time, which is its whole value.
- **`.abydos/` is committed selectively** — `run/` and `backlog/` are the
  project's, everything else is one machine's state. The `.gitignore` in there
  is the rule; do not widen it casually.
