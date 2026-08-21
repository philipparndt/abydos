## 1. Which checkout holds it

- [x] 1.1 `GitWorktrees.holder(of:in:excluding:)` — pure over a list, with an
      async twin that asks git. Nil when nobody has it, which is every other
      refusal.
- [x] 1.2 The primary clone, a worktree and a registration whose directory is
      gone are told apart by `isPrimary` and `isMissing`, both already there.
- [x] 1.3 Tests over the answer: a detached worktree holds nothing — `nil == nil`
      would have made every one of them match a branch nobody named — `ui` is not
      `ui-rework`, and the checkout doing the asking is never offered to itself,
      because a branch held by the window's own project cannot be why a checkout
      failed.

## 2. The offer

- [x] 2.1 A failed checkout asks the question, and a live checkout is offered to
      be opened, as a notification with a button rather than a dialog.
- [x] 2.2 The offer opens it through `AppDelegate.open(projectAt:from:)`, which
      is the door the titlebar, the backlog card, the branches pane and the
      switcher all use — so a window already showing that checkout is raised.
- [x] 2.3 A missing directory is offered a prune, says the registration is there
      and the directory is not, and **does not retry the switch** — it says the
      branch is free and that switching is a second press.
- [x] 2.4 Where nobody holds the branch, git's own message is shown exactly as
      today, including the exit-code fallback for a refusal with nothing on
      stderr.
- [x] 2.5 The sentences live in `BranchInUse`, in `AbydosKit`, where a suite
      reads them without a window.

## 3. Every way in

- [x] 3.1 The titlebar menu and the project switcher, which already shared
      `BranchMenu.checkout` — the refusal path moved inside it.
- [x] 3.2 The branches pane keeps its own checkout — it handles a remote branch
      by making the tracking branch, which the titlebar's does not — and calls
      the same `explainRefusal` with the result.
- [x] 3.3 One `explainRefusal` between the three, so they cannot come to explain
      one refusal differently.

## 4. Watched

- [x] 4.1 Against a scratchpad repository, never a real checkout — one made for
      this, with `ui` in a worktree and a second worktree deleted by hand:

          BRANCH ui: ui is checked out elsewhere — ui is checked out in the
          checkout at …/wt-ui, and git will not have it in two places at once.
          [button: Open wt-ui]
          BRANCH pressed: true
          BRANCH after: project=wt-ui

      The window is on the checkout that holds the branch, opened through the
      door every other way of choosing one uses.
- [x] 4.2 The offer declined: `BRANCH ui: on main in wtrepo` — the window did not
      move, and nothing but the notification happened.
- [x] 4.3 Asked from the worktree about the branch the original clone has: "main
      is checked out in **the main checkout**", and the button reads "Open the
      main checkout" rather than naming a path.
- [x] 4.4 A worktree deleted with `rm -rf`: the offer is "Remove the
      registration", and taking it said "The branch is free now. Switching to it
      is a second press." `git worktree list` afterwards has two entries where it
      had three, and `git checkout gone` then succeeds — **the switch was not
      retried**, which is the promise.
- [x] 4.5 A dirty work tree: `Could not switch to other — error: Your local
      changes to the following files would be overwritten by checkout:` — git's
      own message, no offer, exactly as before.

## 5. Finish

- [x] 5.1 `version-control` says what a held branch offers and what a stale
      registration offers instead. **Nothing existing is made untrue**: the
      capability's fourteen requirements cover the working copy, staging,
      branches, push, the titlebar's list of checkouts and discarding — and none
      of them says anything about a switch that git refuses. The new requirements
      point at *Choosing a checkout opens it as a project*, which they use rather
      than change.
- [x] 5.2 `make test` and `make warnings`, both clean, exit codes trusted.
      `make test exit=0` — 3147 tests in 416 suites, 2 known issues, load 11.3
      over 10 cores. `make warnings exit=0`, four warnings and all four in
      vendored tree-sitter C.
- [x] 5.3 What was ruled out on the way:

      - **Parsing the path out of git's message.** It is right there in
        `fatal: 'ui' is already used by worktree at '/…'` and it is the wrong
        source: a wording is one version of one program's phrasing, and a path
        with a space or a quote in it cannot be parsed out of prose. The worktree
        list states it as a fact.
      - **Checking before switching.** It would pay in the common case for the
        rare one, and git is the authority at the moment it runs — a worktree can
        appear between a check and a checkout.
      - **Taking the branch off the other checkout** — `--force`, `git worktree
        move`, detaching it. Somebody who wants to look at a branch is not asking
        to rearrange their repository.
      - **Doing it silently.** Opening another checkout moves somebody's window;
        the offer says what it will do and waits, which 4.2 shows.
      - **Retrying the switch after a prune.** A prune changes the repository,
        and doing two things from one press is one more than was agreed to.
      - **A second way to open a checkout.** The offer goes through
        `AppDelegate.open(projectAt:from:)`, so a window already showing that
        checkout is raised rather than a second one made.
      - **A dialog.** This is a notification with a button, like every other
        refusal the app can do something about.

      **The two open questions, restated rather than answered:**

      - *Whether the branches pane should mark branches another checkout holds*
        before anybody tries. It lists branches and worktrees in one place and
        has the information, so it could — and it is a second feature, about
        prevention rather than about the refusal. Still open, and worth an item.
      - *What a locked worktree should change.* `isLocked` is known and nothing
        here reads it: a locked worktree can still be opened, so the offer is the
        same. If locking should change the sentence, nothing in this work found
        out what it should say.
