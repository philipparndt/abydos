# 534. A driven run showed a project nobody passed to it

Reported by the agent doing 0525, in passing, while capturing the dependencies
section:

> one capture run came back showing a project under `~/.config` instead of the
> scratchpad copy I passed to `--open` — the app restored its own session

Nothing was typed and nothing was written, and the run was otherwise fine. It is
filed because of what it threatens rather than what it cost.

## Why this matters more than one odd capture

**It is the safety rule.** Agents are told never to drive the app against
anything under `~/dev`, and to copy a project into a scratch directory and open
that. The whole of that instruction rests on `--open <path>` meaning the app
shows that path and nothing else. A run that silently shows something else means
an agent believes it is driving a throwaway copy while looking at — and
potentially typing into — a real one.

That is not hypothetical here. **0522 exists because it already happened**: a
verb ran with no project named, the window came up on whatever the reporter had
last been working in, and `--type` put `C-ircle` into a file in
`abydos-examples` that nobody was editing. The guard 0522 added is still in place
and reads, at `AppDelegate.swift:265`:

    } else if DrivenRun.isActive {
        // **A driven run opens what it was given and nothing else.**
        controller = nil

So the fallback-to-last-project path is closed for a driven run with no project.
And `--open` takes the *first* branch, before any of that:

    if let path = options.projectPath {
        controller = open(projectAt: URL(fileURLWithPath: path, isDirectory: true))

Which is why this report needs reproducing rather than explaining: on the face
of the code it should not be possible, and a guard that is right in the file and
wrong in the run is worth more attention than one that was never written.

## Where to look, without guessing which it is

Listed as places to rule out, not as a diagnosis. One report, no reproduction.

- **`open(projectAt:)` itself.** It raises an already-open window for a project
  rather than opening a second one. What it does when the path does not exist,
  is not a directory, or resolves through a symlink to somewhere already open,
  is worth reading — a scratch copy under `/private/tmp/...` reaches it through
  a symlinked `/tmp` on macOS.
- **Restoring a window's own session.** `Subprojects.resolve` and the session
  machinery put back what a window last had. Whether any of that can *change the
  project* rather than merely restore tabs within one is the sentence the report
  actually makes — "the app restored its own session" — and it is a different
  mechanism from the recent-projects fallback 0522 closed.
- **Whether `~/.config` is a clue or a coincidence.** A project under `~/.config`
  is a plausible "last thing worked in" for this machine. If it is the most
  recent entry in `RecentProjects`, that points back at the fallback and means
  something reached it despite the guard. If it is not, it points at session
  restore. **Check that first — it separates the two candidates in one step.**
- **`DrivenRun.isActive` being false when it should be true.** The guard is
  conditional on it. A capture run that did not count as driven would fall
  through to `RecentProjects.shared.entries.first` legitimately, which would make
  this a question about what counts as driven rather than about session restore
  at all. 0535 is a second case of a capture flag not being recognised, so this
  is not a far-fetched candidate.

## Worth deciding

- **Whether a driven run should refuse rather than substitute.** If the named
  project cannot be opened, opening a different one is the worst available
  answer. Failing loudly — no window, a message on stderr, a non-zero exit —
  is what a harness can act on, and is the same argument 0522 made.
- **Whether the driven guard belongs earlier.** It is currently the *fourth*
  branch. A driven run arguably wants its own decision at the top: it opens what
  it was given, or it fails. Every fallback below is written for somebody
  double-clicking the app.
- **Whether a driven run should say what it opened.** One line naming the
  project root would have turned this from an anomaly somebody noticed into
  something a harness can assert on. Cheap, and it makes the whole class visible.

## Steps

- [ ] Reproduce it, or establish that it cannot be reproduced and say what the
      run actually did — the recent-projects list is the first thing to check
- [ ] A driven run opens the project it was given, or fails in a way a harness
      can see — never a different project
- [ ] A driven run says which project root it opened
- [ ] The scratch-copy-through-`/tmp`-symlink path is checked specifically
- [ ] A test for the refusal case, since that is the one nobody would notice
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
