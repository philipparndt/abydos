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

## Steps

- [ ] Decide whether a staged row offers it, and what it means there
- [ ] Discard Changes on a file, with a confirmation that says what is lost
- [ ] Discard Changes on a folder, saying how many files and how many of them
      are untracked and therefore deleted
- [ ] The confirmation names stash as the recoverable alternative, or a written
      reason it does not
- [ ] Watched in the app on a real working copy: a modified file, an untracked
      file, and a folder holding both
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/version-control.md` says what the project now does
