## Context

Three panes — `ChangesPane` (1,434 lines), `BranchesPane` (1,045) and
`HistoryPane` (824) — each hold their own repository, their own filter field and
their own context menus, and each is a sidebar tool window with a button on the
rail. `AbydosKit/Git` under them is in good shape: `GitStash.drop` works from the
highest index down so renumbering cannot take the wrong entry, `GitStash.rename`
drops and re-stores the same commit and names the recovery command if the second
half fails, `GitTags.recreate` takes anything git can resolve, `GitPatch` builds
a partial patch from chosen lines and `GitWorkingCopy.applyToIndex` applies one.

What is absent from the kit entirely: `fetch`, `pull`, `rebase`, `cherry-pick`,
`revert`, `reset` beyond unstaging, tag creation, and any notion of a backup.

The editor area already takes git's detail: `EditorAreaController.openDiff` and
`.openCommitDiff` exist and are called from `MainWindowController.showDiff` and
`.showCommitDiff`. `LaunchConfigurationsPage` is a full non-file page in the
editor area and its own comment argues the case for one: "Not a dialog… As a tab
it can be left open, switched away from, and come back to."

## Goals / Non-Goals

**Goals:**

- One rail button for git, and one place to ask a question of the repository.
- A verb for every object the tree draws, and no verb without one.
- Branch names that fold on `/`, in the tree everything else here already uses.
- No operation that can lose work without saying so and leaving a way back.
- Fetch and pull, which have never existed.

**Non-Goals:**

- Interactive rebase, three-way conflict editing, and blame archaeology.
  `BranchMenu` already offers `Open in Fork` when Fork is installed; this makes
  that a stated contract rather than a fallback. Abydos owns the git done *while*
  writing code, not the git somebody sits down to do.
- A merge tool. A conflict is reported and named; resolving it is the editor's
  job or Fork's.
- Signing, submodules, LFS, bisect. They belong behind the typed command surface
  if anywhere, and that surface is not in this change.

## Decisions

### The sidebar holds one tree; the editor area holds one page in two tenses

Selecting is a narrow-column job and reading is not. A tree of short names is
exactly right at 300 pt; a graph with lanes and refs, or a file list beside a
diff, is not.

So: anything in the tree that holds files expands to them (the working copy into
staged and unstaged, a stash into what it would restore) and a file opens its
diff where diffs already open. Anything that is a ref opens a page.

*Rejected: a three-segment control inside the sidebar (Working / Refs / Log).* It
keeps all three views in the column that cannot hold two of them, and it puts the
mode switch back — the thing the tree exists to remove.

*Rejected: keeping the three panes and only adding the missing verbs.* It answers
"cannot create a tag" and not "too complicated", and every verb added makes the
second worse.

*Rejected: retiring the branch list because the log already draws refs on
commits.* True and not enough: the list is what you select *with*, and a picker
that closes is not a place to look things up in.

### The Log page and the Commit page are one page class

Both are a list of changes on the left, the diff of the selected one on the
right, and what to do with the set along the bottom. That is not a coincidence to
be tidied later: the working copy is the commit that has not happened yet, which
is why it sits in the tree above the stashes and branches as a thing of the same
kind. Build the page for the log tense; the commit tense is the same view pointed
at what is staged.

*Trade-off recorded:* the sidebar keeps a one-line subject field and `Commit ⌘⏎`
for the commit that needs no thought. Two ways to commit can drift into two
features; the rule that stops it is that the field *is* the page's subject line,
and `…` opens the page with whatever is typed already in it.

*Rejected: taking committing out of the sidebar entirely.* The one-line commit is
the common one and a trip to a tab for it is worse than the 70 pt message box
this change is removing.

### Backup refs are real branches under `backup/`, and uncommitted work is captured with `git stash create`

An operation is destructive when nothing left on this machine afterwards can put
it back. Those, and only those, ask — and each leaves a ref first.

Committed work is kept by pointing a branch at the old tip. Uncommitted work is
kept by `git stash create`, which writes a commit for the working copy and,
unlike `stash push`, touches neither the working copy nor the stash list; a
branch is then pointed at that commit. Nothing on screen moves.

*Rejected: relying on the reflog.* It is the right answer for a person at a
prompt and the wrong one for a promise: reflog entries for unreachable commits
expire after 30 days by default and `gc` collects what they pointed at. A branch
is reachable and survives.

*Rejected: a private namespace, `refs/abydos/backup/…`.* Invisible to
`git branch`, to `git log --all`, and to anybody who has never heard of this app.
Safety nobody can find is not safety. The cost of visible refs — clutter in the
branch list — is paid by the branch-folder work in this same change, which folds
the whole of `backup/` into one row.

*Rejected: tags.* They are pushed, and a private near-miss is not something to
publish.

*Explicitly not insured:* force-pushing a branch. No local ref can recover
somebody else's commits from a remote, and pretending otherwise would be the
worst lie in the feature. That one is refused until the count of what would be
overwritten has been read.

*Rule kept deliberately narrow:* staging, unstaging, stashing, fetching, creating
anything and applying a stash while keeping it are all recoverable and stay
silent. A dialog in front of a safe operation is what teaches people to dismiss
the one in front of an unsafe one. Only the choice that loses nothing may be
remembered — `Always stash and switch` can be ticked, `Always discard` cannot.

### The repository outranks the app about how it pulls

`Rebase instead of merge` and `Stash and reapply local changes` are `--rebase`
and `--autostash`. Both are remembered as app settings — but when `pull.rebase`
is set in the repository's own config, that is what the dialog opens on, and it
says so. A project that has decided how it pulls should not be quietly overridden
by somebody's preference in another program.

### The refs tree, the changes tree and the project tree share one builder

`GitChangeNode` already builds a tree from `/`-separated paths, keeps collapse
state by path across a full rebuild, and its own comment says it is the "same
arrangement as the project tree, and for the same reason". A branch name is a
path. Generalise the builder over a path and a payload rather than writing a
third one.

Two rules that are not obvious and both matter: a folder holding exactly one
branch stays flat, because a folder that exists to hold one row has turned one
row into two and said nothing; and filtering flattens the tree to full names,
because a tree you must expand to reach a name you just typed is worse than no
tree.

### Claude drafts the message through the CLI, from what is staged

`claude -p` over the staged diff, seeded with the last twenty subjects from
`git log` so the draft matches this project's voice rather than a generic one.
The staged diff and not the working copy: the draft describes the commit being
made, not everything on disk.

*Rejected: calling the API directly.* It adds a dependency and a credential path
to an app that already meets Claude through its terminals and
`ClaudeHookRunner`. The button is simply absent when `claude` is not on the
`PATH`.

It fills two fields and stops. Nothing is staged, nothing is committed, both
fields stay editable, and `Commit` is never disabled while it is thinking — a
slow answer must not become a blocked one. That it sends the diff to Anthropic is
said plainly, once, per project, before the first time.

## Risks / Trade-offs

- **A dialog nobody reads** → the list that asks stays as short as the spec's
  table and no shorter, and each one leads with a number: "4 commits leave main"
  is read where "this cannot be undone" is not.
- **Backup refs pile up, and a ref keeps its commits from being collected** →
  folded into one row by the branch-folder work, swept on a timer whose default
  is 30 days, and the sweep says what it took.
- **⌘3 and ⌘6 move** → the only outright break. Both open the same tool for a
  release, with a toast naming the new key.
- **One tree carrying six kinds of row** — changed files, stash entries,
  branches, folders of branches, tags, worktrees → coherent because each is a
  thing this repository holds; the moment a seventh wants in, the answer is a
  page.
- **Two densities of the same data** (a tree row and a page row) → one loader and
  one model between them; two row views over one model is fine, two models is
  not.
- **`stash push --staged` needs git 2.35** → checked once and the hunk-level
  stash offered only when it is there.

## Migration Plan

Eight steps, each shippable alone and in this order. The first two go together:
step 1 adds reset and rebase, which are the reason step 2 exists.

1. Commit verbs in the log, and the tag picker.
2. The safety net under them.
3. Branch-name folders — `backup/` folds itself away for free.
4. Stashes made first class.
5. The header, fetch, pull and the pull dialog.
6. The editor page, log tense.
7. The same page, commit tense — with the Claude draft on it.
8. One tree, one tool item, and the rail shortcuts move.

Rollback: steps 1–5 add verbs and dialogs to panes that keep their shape, so each
reverts on its own. Steps 6–8 move views; the panes keep their files and become
the page's contents, so a revert is a re-parenting rather than a rewrite.

## Open Questions

- ~~**How the clean-apply check for a stash is done.**~~ **Settled: neither.**
  `merge-tree --write-tree` answers it entirely in the object database, so there
  is no throwaway index to write or clean up. The side it merges *into* is the
  working copy rather than `HEAD` — the question is whether the stash goes back
  over what is there now — and `GitBackup.captureWorkingCopy` already gives the
  working copy a commit to stand for it without writing anything. Old git gets
  `.unknown`; a check that guessed "clean" would be worse than no check.
- **Whether the project tree folds into the generalised builder too.** Still
  open, and now worth more than it was. `PathTree` is shared by the changes tree
  and the refs tree; the project tree still has its own. What this change learnt
  the hard way is that the cost of *not* sharing is not tidiness — it is that
  the refs list was a flat table pretending to be a tree, and every tree
  behaviour written by hand for it was wrong: the disclosure triangles, the
  arrow keys, the page keys, keeping focus across a rebuild, the indentation.
  All of it went away by becoming an `NSOutlineView` like the other two. The
  remaining duplication is `HistoryPane`, which is still a table keeping its
  selection by hand.
- ~~**What a conflict banner offers.**~~ **Settled on 2026-08-23: three things.**
  *Open the conflicted files*, because that is the work and it is what somebody
  reached for the banner to do. *Open in Fork*, which is this change's stated
  contract for the git you sit down to do — a three-way merge editor is
  explicitly not being built here, so the banner is where the handoff belongs.
  And *copy an AI prompt to solve the conflicts* — the diff of the conflicted
  hunks with both sides and enough of the surrounding history to be answerable,
  on the pasteboard, ready to paste into a session in this app's own terminal.
  The third is the one worth arguing for: an IDE whose thesis is agents in the
  terminal should hand a conflict to one rather than describe it.
  Not abort: the banner is about resolving, and abandoning a merge belongs on
  the operation that started it, where the count of what would be lost is known.
- **Whether the backup sweep runs on open or on a timer.** Still open, and
  nothing runs it yet: `GitBackup.sweep(olderThan:now:in:)` exists and is tested,
  the setting exists and is written down, and the only way to call it is the
  verb on the `backup/` folder. That is deliberate for a first release — a
  feature whose whole promise is "nothing is lost" should not begin by deleting
  things on a schedule nobody has watched yet.
