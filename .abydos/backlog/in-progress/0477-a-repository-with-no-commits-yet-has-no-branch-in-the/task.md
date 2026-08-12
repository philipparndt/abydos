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

## What was decided

**`symbolic-ref --quiet --short HEAD`**, in `GitRepository.head(in:)`, which is
now the only place in the app that asks which branch the work tree is on. It is
plumbing, so its output is a promise rather than a convenience; it has been
there since long before git 2.22, which `branch --show-current` needs; and it
fails for a detached HEAD instead of printing an empty line, which is one rule
fewer to remember than porcelain's two.

It answers a three-state `GitRepository.Head` — `.branch(name)`, `.unborn(name)`,
`.detached` — because there are three states and the app had two. Whether a
branch has anything on it is a second question, `rev-parse --verify --quiet
HEAD`, asked in parallel with the first: two processes cost what one does, and
the pair is what tells `.unborn` from `.branch`.

The five callers now share it: `GitRepository.refresh`, `BranchMenu.currentBranch`
(and through it `ProjectSwitcherPopover`, which was the fifth and was not in the
report), `GitPush.state`, and the titlebar through `MainWindowController`.

**The titlebar shows the name, dimmed** — the colour the `⇧⌘P` hint beside it is
drawn in — with `On main — no commits yet` on the tooltip. Nothing was the bug.
The name at full weight would be the only thing in the window not admitting the
branch is empty: the commit page, the push button and the branch menu all read
differently on it. See `images/abydos-platform-titlebar.png`, which is the
reported repository.

**Push keeps refusing, and now says what it is refusing.** `git push -u origin
main` from an unborn branch has no ref to send, so the button stays disabled —
but `GitPush.State` carries the branch and a `hasCommits` flag instead of coming
back nil, and the tooltip reads `“main” has no commits yet` where it used to
read `Push this branch`, which is the one thing that repository cannot do.

## The rest of the git surface, walked in a repository with no commits

Two more things were broken and are fixed here:

- **The branch menu did not open at all.** `BranchMenu.show` bails when `git
  branch` lists nothing, and an unborn branch is in no list git can produce —
  `git branch` reads refs, and there is no ref. So fixing the question the pill
  asks would have gained nothing: the menu behind it stayed shut, taking Open in
  Fork and Open on <host> with it. The branch is now added to the menu itself,
  ticked and disabled.
- **Amend was live and produced a raw git error.** With nothing committed,
  ticking Amend and pressing the button put `fatal: You have nothing to amend`
  on screen. The checkbox is now disabled with a tooltip, from the same
  `hasCommits`.

Found and deliberately left alone, because git's own message is already the
clearest thing anybody could be shown and none of them is silent:

- `git stash push` — `You do not have the initial commit yet`. Reachable from
  the changes pane, and it surfaces through the existing failure path.
- `git worktree add` — `fatal: invalid reference: HEAD`. Reachable from the
  branches pane and from `BacklogRunner`, which cannot make a worktree of a
  repository with no commits and says so.
- `GitTags.likelySource` falls back to the *string* `"HEAD"`, so creating a tag
  fails. Needs somebody to open the tag dialog on an empty repository.

Found and correct as they stand, verified by reading the arguments:

- **The diff view and line staging never name `HEAD`.** `git diff --cached`
  special-cases an unborn HEAD against the empty tree, so a staged file shows as
  an addition; the untracked path is `diff --no-index -- /dev/null <path>`; and
  `apply --cached`, `restore --staged` and `reset -- <paths>` all work with no
  HEAD. Confirmed on screen — the commit page's tree, the diff and staging are
  all correct in the reported repository.
- **Committing needs no parent.** `git commit -m` builds the first commit; only
  `--amend` needs one, which is the case above.
- **blame, log, history and the unpushed count** all fail and are already read as
  empty: blame returns no lines and the gutter is blank, `git log` returns
  nothing and the history pane says "No commits.", `rev-list --count HEAD` parses
  as 0. Nothing to change.
- **`git worktree list --porcelain`** answers `HEAD 0000…000` / `branch
  refs/heads/main` and parses fine.

There is no `HEAD~1`, `HEAD^`, `merge-base` or `describe` anywhere in `Sources/`,
so the "a first commit has no parent" worry turned out to have no sites at all —
the damage was all in naming HEAD as a revision, not in walking back from it.

## Ruled out

- **`git branch --show-current`.** Same answer, but porcelain, git 2.22 or
  later, and an empty line rather than a failure for a detached HEAD. Nothing to
  gain for a second output convention to remember.
- **Reading `.git/HEAD` directly.** It is one line and it is tempting. It is
  also wrong for a linked worktree, wrong for `--separate-git-dir`, and it
  would be this app's own parser for a file format git owns.
- **`git status --porcelain=v2 --branch`**, whose header carries `branch.head`
  and `branch.oid (initial)` and would have answered both questions in the one
  call `refresh` already makes. Left alone: it means moving the status parser
  from v1 to v2, which is a change to the code that colours every row in the
  navigator, for one subprocess.
- **Keeping the last known branch when git fails.** `refresh` used to assign
  only on exit 0, which quietly kept a stale name. The commonest failure it was
  covering for was exactly this bug, and that now has an answer; a stale branch
  through a real failure is worse than none, so the state is assigned
  unconditionally.
- **Saying `main (no commits)` in the titlebar.** The capsule has one line and
  the project name shares it. Dimming carries the same fact in no extra width,
  and the sentence is on the tooltip where there is room for it.
- **Letting the unborn branch be checked out from the branch menu.** It is the
  branch already checked out, and `git checkout` of a branch with no commits is
  an error rather than a no-op. It is a row that says where you are, not a
  destination.

## Estimate

2026-08-12 06:29 — about twenty minutes left

## Steps

- [x] One place answers "which branch", and the four callers use it
- [x] An unborn branch answers with its name; a detached HEAD still answers nil
- [x] The titlebar shows something honest in a repository with no commits
- [x] Walk the rest of the git surface in that repository — diff, commit, push,
      blame, the panel — and say what else assumes a commit
- [x] The branch menu opens on a repository with no commits — found on the walk,
      and without it the pill's fix showed nothing
- [x] Amend is not offered where there is nothing to amend — likewise
- [x] Watch it in `~/dev/abydos-platform`, which is where it was reported
- [x] Write down here what was ruled out on the way
- [x] `spec/version-control.md` says what the project now does
