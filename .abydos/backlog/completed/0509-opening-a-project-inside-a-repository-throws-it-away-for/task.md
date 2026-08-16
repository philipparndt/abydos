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

## Reproduced, out of the app, in one pair of lines

`--report-cwd` printed only where the shell was, which is the half of this that
is *correct* in both builds. It now prints the project beside it, and the tabs,
because the tabs are what the switch destroys. Same build, same command, the
only difference being the flag that turns 0451's guard on:

    Abydos --open …/abydos-examples/cadova-models --report-cwd
    CWD 1s: …/abydos-examples/cadova-models  project=abydos-examples subproject=cadova-models tabs=[Extrusion.swift main.swift]

    …the same, plus --screenshot …/before.png --delay 11
    CWD 1s: …/abydos-examples/cadova-models  project=cadova-models subproject=whole tabs=[main.swift]

One second in, and already gone. The shell is in `cadova-models` on both lines
and never moves off it for the whole run — so the directory the window is
following is not a move at all, and `Extrusion.swift` on the first line is
`abydos-examples`'s own session restored over the file that was asked for.
The `subproject=cadova-models` on it is that stored session's subproject chip,
which is how the titlebar goes on claiming the narrowing after the project
underneath it has been swapped.

## Watched in the app, after

Same command as the first line above, on the build with the rule in it, and the
tmux pane put back in `cadova-models` first so the run is the reported one:

    CWD 1s: …/cadova-models  project=cadova-models subproject=whole tabs=[main.swift]
    CWD 9s: …/cadova-models  project=cadova-models subproject=whole tabs=[main.swift]

and the move that must keep working, typed into the pane rather than simulated:

    Abydos --open …/cadova-models --terminal --run "cd .." --report-cwd
    CWD 1s: …/abydos-examples/cadova-models  project=cadova-models    tabs=[main.swift]
    CWD 2s: …/abydos-examples               project=abydos-examples  tabs=[]

One second on the project it was opened on, and the moment the shell really
walks out, the window is with it.

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

## What was decided: none of the three, and the second question is the answer

The three candidates are all about *when* a terminal's directory may be
believed. None of them is needed, because the fault is not in the timing of the
answer — it is in the question. `ProjectRoot.find` answers **"which repository
is this directory in"**, and the window was reading it as **"where has the shell
gone"**. Those are the same question only while the project *is* its repository,
which is why nobody had seen this until a project was opened at a subdirectory.

So the rule is one line, and it is the one `terminalDirectoryChanged` has always
claimed in its own comment — *"moving between directories inside one changes
nothing"* — said about **the project** rather than about the repository:

    a directory inside the project the window is already on is not a move.

`ProjectRoot.projectToFollow(from:current:)` in `AbydosKit` is that rule, and
`terminalDirectoryChanged` asks it instead of `find`. A shell that steps *out*
of the project is genuinely somewhere else and is followed exactly as before.

This is the item's second question — whether a project opened at a subdirectory
should resist widening — answered as **yes, and only that far**. It resists
while the shell is still inside it, which is the case where nothing happened;
it does not resist a shell that walks out, because a project that could never be
left would make following the terminal mean nothing for every project that is
not its own git root, and `cd ..` is the case the reporter would hit next.

### Why not the other three

- **"Do not follow a directory the terminal was *restored* into."** The right
  description of the symptom and the wrong place to fix it. It needs a flag
  threaded from `restoreTerminals` through `BottomPanel.reportWorkingDirectory`
  into the window, it is a fact about *this launch* rather than about anything
  true of the program, and it is only testable by launching the app — there is
  no test target for `AbydosApp`. And it would not have fixed the general case:
  the old code asked `find` about every directory a shell reported, so `cd
  Sources` inside `cadova-models`, hours later, in a terminal nobody restored,
  threw the project away just as readily. The chosen rule covers that one too,
  and it was run rather than argued:

      Abydos --open …/cadova-models --terminal --run "cd Sources" --report-cwd
      CWD 1s: …/cadova-models          project=cadova-models tabs=[main.swift]
      CWD 2s: …/cadova-models/Sources  project=cadova-models tabs=[main.swift]
- **"Do not follow until the terminal has reported twice."** Cheaper still and
  wrong in a way that is hard to see: `activeTerminalChanged` deliberately
  clears `lastReportedDirectory` so that *selecting another terminal tab* is
  followed at once, which is the feature working as designed. A "second report"
  rule either breaks that or has to make an exception for it, and either way it
  is a heuristic about counting rather than a statement about projects. It also
  leaves the bug in place for any shell that does report twice.
- **"Never switch away from a project somebody named explicitly."** This is the
  feature turned off for exactly the people using it. `--open` and the recent
  projects list are how every project gets opened; there is no such thing as a
  project the window is on that nobody named. It would have made the reported
  case work and following the terminal useless.

**The third question — what happens to the tabs — is not addressed here** and no
step was taken for it. The restore still replaces what is open, without asking,
whenever a switch does happen. That is now only on real moves, which is the
whole of what this item claimed; a switch somebody caused by walking their shell
into another project restoring that project's tabs is the feature rather than
the fault. Worth its own item, and it is not this one.

## Ruled out, and other things found on the way

- **The session, and the tabs it restores.** 0507 had already ruled it out by
  moving `.abydos` away; the reproduction above rules it out again from the
  other end, because the *same session* is restored on both lines and only the
  screenshot flag differs. What the session holds was never wrong: the terminal
  it names is in `cadova-models`, and that is where the shell was.
- **The subproject chip.** It reads `subproject=cadova-models` on the broken
  line, which looks like the narrowing surviving the switch. It is not that: the
  window is on `abydos-examples`, whose *own* stored session names
  `cadova-models` as its subproject, so the chip is right about a project nobody
  asked for. A chip is not a defence against this and could not have been one.
- **`ProjectRoot.find` itself.** It is correct and is left alone. It answers
  "which repository is this directory in", every one of its seven existing tests
  is about that question, and two callers — `Project.root(containing:)`, which
  is what `ideai path/to/file.go` opens, and `Project.loadGit` — want exactly
  that answer. The caller asking it the wrong question is the fault, so the new
  rule sits beside it under a name that says which question it answers.
- **Making it a rule about restoring, in the panel.** See above: it needs a flag
  threaded through three objects, it is only true of a launch, and there is no
  test target for `AbydosApp` to hold it. What is *not* ruled out is the case it
  would have covered and this does not: a tmux session the app reattaches to
  whose shell has been left in another checkout since yesterday really is in
  another checkout, and the window follows it there on the next launch. Measured
  by accident, when a `cd ..` from one of these runs stayed in the tmux server
  and the next launch opened on `abydos-examples`. That is not this bug — the
  shell genuinely moved, only earlier — but it is the closest thing to it left
  standing, and somebody who finds it unbearable has the whole of the "restored"
  candidate waiting above.
- **Whether following is worth having at all.** Not reopened. The screenshot
  guard is the one place the hazard had been seen, and 0451 turned following
  *off* there rather than fixing it; the temptation was to generalise that. It
  would have cost the feature its purpose, and the guard stays as it is for the
  different reason it was written: a capture is of a named project and must not
  follow a shell anywhere at all, including somewhere the new rule would rightly
  follow it.
- **Which spec file owns this.** `terminal.md`, not `sessions.md`, and the two
  are close enough to be worth saying why. `sessions.md` is "what a project
  remembers between one sitting and the next", and nothing about what is
  remembered changes here: the same session file, restored into a window that no
  longer misreads it, comes back correctly. `terminal.md` is what a pane in the
  bottom panel is and what the app does with one, and its opening already lists
  "following a terminal to its pane's directory" among them. The rule is about
  what a pane's directory *means* to the window, so it goes where the pane is
  described.

## Steps

- [x] An instrument that says which project the window is on, second by second,
      beside where the terminal is — `--report-cwd` says only the second half
- [x] Reproduce it from outside the app, without a screenshot run to mask it
- [x] Decide what a restored terminal's directory means, and write it down
- [x] Opening a project inside a repository keeps that project
- [x] A real `cd` somewhere else still follows, and there is a check for both
- [x] Answer the second question — whether a project opened at a subdirectory
      should resist widening at all — in here, whether or not it is acted on
- [x] Watched: open `abydos-examples/cadova-models`, wait, and the window is
      still on it with its own tabs
- [x] `make test` and `make warnings` are clean — 2676 tests, and
      `foldComputationIsReasonableOnHugeFile` failed the whole-suite run and
      passed alone at 8.6 s against its 10 s bound, which is that test measuring
      a machine with four other jobs on it rather than anything in this change
- [x] Write down here what was ruled out on the way
- [x] `spec/sessions.md` or `spec/terminal.md` says what the project now does —
      whichever owns following the terminal

## Estimate

2026-08-16 19:41 — done bar the fold
