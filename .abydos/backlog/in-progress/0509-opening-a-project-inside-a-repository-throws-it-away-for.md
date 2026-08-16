# 509. Opening a project inside a repository throws it away for the repository

Open `abydos-examples/cadova-models` — a directory inside a git repository —
and about a second later the window is showing `abydos-examples` instead, with
that project's tabs restored over the ones just opened.

Found while 0507 was chasing an empty Cadova pane. The pane was fine; the
window had left the project.

    MainWindowController.terminalDirectoryChanged(to:)
      → switchProject(to:followingTerminal: true)
      → EditorAreaController.restore(ProjectSession)
      → open(fileURL: …/Extrusion.swift)

The session restores a terminal sitting in the project. The window follows its
terminal. `ProjectRoot.find(from:)` walks up from the terminal's directory to
the **git root** and answers `abydos-examples`, which is not the project that
was opened — so the window switches to it and restores its tabs.

**The terminal never moved.** Following it is right when somebody `cd`s
somewhere else; here the shell is exactly where it was put, and the answer to
"which project is this directory in" is being taken as "somebody has moved".

Reproduced with `--file`, without `--file`, and with the project's own
`.abydos` moved away, so neither the session nor the argument parsing is the
cause. It costs the tabs somebody opened, and it cost 0499 its watching — the
scratchpad spike it was tested against was not inside another repository, so
this never fired.

## What the code already knows

`terminalDirectoryChanged` (`MainWindowController.swift:2006`) already refuses
to switch during a screenshot run — 0451's rule, with a comment that names this
exact hazard: *"a restored tmux session whose shell sits in another checkout
would quietly swap it for that one — which is a screenshot of the wrong
program, taken without complaint."* That is this bug, seen once and guarded
only where a picture was being taken. The same sentence is true when nobody is
photographing anything.

It also gives the item its cheapest test: the same command with `--screenshot`
keeps its Cadova pane and without it loses it.

## Worth deciding

- **What a terminal's directory should mean when it has not changed.** The
  switch is right for a `cd` and wrong for a restore. Whether the fix is "do not
  follow a directory the terminal was restored into", "do not follow until the
  terminal has reported twice", or "never switch away from a project somebody
  named explicitly" is the item, and they behave differently for somebody who
  really does `cd ..` into the parent repository.
- **Whether a subdirectory project should resist at all.** A project opened at
  `cadova-models` is a deliberate narrowing — the subproject chip in the
  titlebar says so. Following a terminal to the repository root undoes that
  choice silently. There may be a rule here about never widening a scope the
  person chose, independent of terminals.
- **What happens to the tabs.** The restore is what destroys work in progress,
  and it happens without asking. Even with the switch made deliberate, throwing
  away open tabs for a project change is worth looking at.

## Steps

- [ ] An instrument that says which project the window is on, second by second,
      beside where the terminal is — `--report-cwd` says only the second half
- [ ] Reproduce it from outside the app, without a screenshot run to mask it
- [ ] Decide what a restored terminal's directory means, and write it down
- [ ] Opening a project inside a repository keeps that project
- [ ] A real `cd` somewhere else still follows, and there is a check for both
- [ ] Answer the second question — whether a project opened at a subdirectory
      should resist widening at all — in here, whether or not it is acted on
- [ ] Watched: open `abydos-examples/cadova-models`, wait, and the window is
      still on it with its own tabs
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/sessions.md` or `spec/terminal.md` says what the project now does —
      whichever owns following the terminal

## Estimate

2026-08-16 19:05 — about two hours left
