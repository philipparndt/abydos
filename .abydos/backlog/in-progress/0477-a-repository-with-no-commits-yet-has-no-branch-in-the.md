# 477. A repository with no commits yet has no branch in the titlebar

> in this freshly created repo: ~/dev/abydos-platform there is no branch and
> nothing shown for git in the title bar.

`git init` and nothing committed. The repository is real, `main` exists as the
name HEAD points at, the working copy is full of untracked files — and the app
shows nothing at all.

## What it is, measured in that repository

    $ git rev-parse --abbrev-ref HEAD
    fatal: ambiguous argument 'HEAD': unknown revision or path not in the working tree.

    $ git symbolic-ref --short HEAD      → main    (exit 0)
    $ git branch --show-current          → main    (exit 0)
    $ cat .git/HEAD                      → ref: refs/heads/main

`rev-parse --abbrev-ref HEAD` **resolves the commit and then names it**, so on an
unborn branch it fails outright rather than answering. `symbolic-ref` and `branch
--show-current` read the reference itself and answer correctly, because the branch
name exists from `git init` — what does not exist is a commit for it to point at.

`GitRepository.refresh()` guards on `exitCode == 0`, so `branchName` stays nil, and
the titlebar has nothing to show. `git status --porcelain` works perfectly in this
state — it is only the branch that is missing.

## Four places ask, and all four ask the same wrong question

- `Sources/AbydosKit/Git/GitRepository.swift:76` — the titlebar's branch, which is
  the report.
- `Sources/AbydosApp/Titlebar/BranchMenu.swift:130` — the branch menu, with a
  comment explaining that it asks git rather than the cache precisely so a fresh
  repository answers. It then asks the one question a fresh repository cannot.
- `Sources/AbydosKit/Git/GitPush.swift:49` — whose comment already says *"Detached,
  or a repository with no commits: there is no branch to push"*, so this one knows.
  Whether that stays true is a decision, not an oversight: `git push -u origin
  main` from an unborn branch fails, but the branch name is knowable and the right
  refusal may be a sentence rather than silence.
- `Sources/AbydosApp/MainWindowController.swift:3607` asks
  `symbolic-ref refs/remotes/origin/HEAD`, which is a different question and is
  not affected.

**`HEAD` as an answer means detached**, and all four turn that into nil correctly.
That behaviour has to survive: `symbolic-ref --short HEAD` *fails* when detached
rather than printing `HEAD`, so a naive swap changes how a detached checkout reads.
Whichever command is chosen, both states need a test.

## Worth deciding

- **Which command.** `symbolic-ref --short HEAD` is plumbing and stable;
  `branch --show-current` is porcelain, needs git 2.22, and prints nothing when
  detached rather than failing. Either works; say which and why, and put it in
  *one* place that all four callers use, since the interesting part of this bug is
  that the same mistake is written out four times.
- **What the titlebar says when a branch has no commits.** `main` alone may
  mislead — nothing is on it, and the commit dialog, the push button and the
  branch menu all behave differently there. Something quieter than a normal branch
  chip may be right, and this is the item that can see the whole set.
- **What else assumes a commit exists.** The diff view, the commit dialog's tree
  (0455), blame, the git panel: a first commit has no parent, so `HEAD~1` is not a
  thing anywhere in that repository. Look before deciding this is a one-line fix.

## Steps

- [ ] One place answers "which branch", and the four callers use it
- [ ] An unborn branch answers with its name; a detached HEAD still answers nil
- [ ] The titlebar shows something honest in a repository with no commits
- [ ] Walk the rest of the git surface in that repository — diff, commit, push,
      blame, the panel — and say what else assumes a commit
- [ ] Watch it in `~/dev/abydos-platform`, which is where it was reported
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does
