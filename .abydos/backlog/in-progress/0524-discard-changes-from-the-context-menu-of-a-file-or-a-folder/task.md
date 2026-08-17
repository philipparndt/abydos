# 524. Discard changes, from the context menu of a file or a folder

> in the git view there should be an action in the context menu of files and
> folders to discards changes

The changes pane's menu offers Stage/Unstage, Add to .gitignore, Stash This
File, Stash All Changes, Reveal in Finder and Copy Path
(`ChangesPane.swift:892`). Throwing a change away is the one thing somebody
does in that pane that it cannot do.

## Most of it already exists

- **The git side is written.** `GitWorkingCopy.discard(paths:in:)`
  (`GitWorkingCopy.swift:199`) runs `clean -fd` and then `checkout --`, and its
  comment already says untracked files are removed. It takes paths, so a folder
  is not a special case.
- **The wording exists.** The diff view has *Discard Selected Lines*
  (`DiffView.swift:239`) for a run of lines, offered only when the hunk is not
  staged. That is the same action one level up, and the two should read as the
  same word for the same thing.
- **The folder wording exists.** Stage/Unstage over a folder says how many files
  it is about to take — *"Stage “Sources” (40 files)"* — and the comment there
  says why: the difference between one file and forty is the whole reason
  folder staging is worth being careful with. Discard needs that more, not less.

## What has to be decided, and it is the substance of the item

- **It must ask.** Everything else in that menu is recoverable: a stash can be
  popped, staging can be unstaged, a `.gitignore` line can be deleted. Discard
  is the only entry with no way back, and for untracked files there is not even
  a git object left — `clean -fd` deletes them off the disk. So it takes a
  confirmation, and the confirmation has to say **how many files** and **that
  untracked ones are deleted rather than reverted**. Those are two different
  losses and the second one surprises people.
- **Whether it is offered on a staged row.** `checkout --` restores the work
  tree from the index, so on a staged file it would throw away nothing that is
  staged — the change would survive, staged, and the row would not go away.
  Either the entry is hidden for staged rows the way the diff view hides it for
  staged hunks, or it means `restore --staged --worktree` and says so. Pick one
  deliberately; the confusing version is the one that half works.
- **Whether Stash is offered as the safe alternative.** The pane already has
  stash, which is discard with a way back. Naming it in the confirmation is
  cheap and is the kind of thing this program does elsewhere.
- **What it does to a folder with a mix.** Untracked and modified files under
  one folder are two different operations on one gesture. The count in the
  title should probably say both, and the confirmation certainly should.

## What was decided

- **A staged row is not offered it.** Hidden, the way the diff view hides
  *Discard Selected Lines* over a staged hunk. `restore --staged --worktree` was
  the other candidate and was rejected on the case that makes two lists worth
  having: a file staged and then edited again is a row in *each* list, and
  discarding it from the staged row would also take the later edit — a loss
  shown only in the other list, by a gesture aimed at this one. Unstaging first
  is recoverable, it is the top item of the same menu, and it puts the row where
  discard already is.
- **The verb changes when nothing can be restored.** Over a file git has never
  seen, *Discard Changes* is false: there are no changes, there is a file, and
  it is about to stop existing. The entry reads *Delete “new.swift”…* there, and
  *Delete “Generated” (3 files)…* for a folder holding nothing else. The mixed
  case keeps *Discard Changes* and says the other number: *Discard Changes in
  “Sources” (40 files, 12 untracked)…*.
- **Stash is named in the sentence, not added as a button.** A third button was
  considered and dropped: it would make the confirmation a three-way decision at
  the moment somebody is being asked to be careful about one thing, and the
  stash prompt it opens asks its own question straight afterwards.

## Ruled out on the way

- **Handing `checkout` the same paths as `clean`.** This is the bug that was
  underneath the whole item. `git checkout -- <path>` fails with *"pathspec did
  not match any file(s) known to git"* when nothing tracked lives under the
  path, and it validates **every** pathspec before restoring **anything** — so
  discarding one untracked file put a git error on screen for an operation that
  had already worked, and discarding a selection holding one untracked file and
  one modified file deleted the untracked one and then reverted nothing.
  `discard` now asks `git ls-files -z --` for the paths first and gives
  `checkout` only the ones git has something under. A folder still goes as one
  argument; the answer is only used to decide *which* of the clicked paths to
  pass on.
- **Expanding a folder into its files for `checkout`.** That would have fixed
  the pathspec failure too, and it throws away the thing folder staging exists
  for: one argument instead of forty, and an error message somebody can read.
- **`clean -fdx`.** Never. Ignored files are not changes, and taking somebody's
  build output out from under them because they discarded a folder is not what
  they asked for. `-fd` leaves them.
- **Offering it over a conflict.** `git checkout -- <unmerged path>` refuses
  outright, so the entry would have been one that always fails. Throwing away a
  half-resolved merge is a real thing to want and it has more than one answer
  (`--ours`, `--theirs`, back to the merge's start); it is a separate item, not
  a fourth meaning for this word. The entry is hidden when anything covered is
  conflicted.
- **Adding a Discard All Changes to the empty-space menu**, beside *Stash All
  Changes*. The pane already has one gesture that destroys everything at once
  and it is recoverable; an irreversible one, reachable by right-clicking
  nothing in particular, is not worth the row.
- **Driving the menu itself from the command line.** `NSTableView.clickedRow` is
  set by the event and by nothing else, so a script cannot pop this menu open on
  a chosen row the way `BranchesPane.showMenuForTesting` can — that pane's menu
  is built from the *selection*. The question this entry turns on is wording and
  counting, so what the pane exposes instead is what the menu would say and what
  git would be given (`offer:`, `offer-staged:`, `discard:` steps), and the
  wording itself is in `AbydosKit` where a test can check the numbers.

## What is not done, and why

The Bash tool in the session that did this work was allowed to read files and
almost nothing else: `make`, `swift`, `git` writes and `abydos-backlog` all came
back *"This command requires approval"*, in a session with nobody to ask. So:

- **Nothing here has been compiled or run.** The two steps below are unticked
  because they are genuinely not done, not because they were forgotten. The
  tests in `Tests/AbydosKitTests/GitDiscardTests.swift` are written and have
  never been executed.
- **The item has not been through `abydos-backlog done 524`.** It is still in
  `in-progress/`, now as a folder, with the delta in `spec/version-control.md`
  beside this file, unfolded. Nothing has been committed either.

The next person picks this up by running `make test`, `make warnings`, then the
watch below, then `abydos-backlog done 524`.

## Steps

- [x] Decide whether a staged row offers it, and what it means there
- [x] Discard Changes on a file, with a confirmation that says what is lost
- [x] Discard Changes on a folder, saying how many files and how many of them
      are untracked and therefore deleted
- [x] The confirmation names stash as the recoverable alternative, or a written
      reason it does not
- [x] `checkout` is only given paths git tracks something under, so an untracked
      file in the selection stops aborting the whole restore
- [x] `offer:`, `offer-staged:` and `discard:` steps on `--changes-tree`, so the
      offer and the loss can be read from the command line
- [x] Tests for the counting, the wording, and the git side against a real
      repository
- [ ] Watched in the app on a real working copy: a modified file, an untracked
      file, and a folder holding both
- [ ] `make test` and `make warnings` are clean
- [x] Write down here what was ruled out on the way
- [ ] `spec/version-control.md` says what the project now does — the delta is
      written; folding it is `abydos-backlog done 524`, which could not be run

## Estimate

2026-08-17 08:13 — the work is written; half an hour of building, running the
suite and watching it in the app, in a session that is allowed to do those
