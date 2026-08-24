The kit work comes first in every group: `AbydosKit` holds no view code, so each
of these is testable without a window and each lands on its own.

Nothing in `.abydos/backlog/spec` is made untrue — that backlog was dropped on
2026-08-19 and its account moved to `openspec/specs`. What this makes untrue is
`openspec/specs/version-control` and `openspec/specs/left-rail`, and the delta in
`specs/` says how.

## 1. The verbs that do not exist

- [x] 1.1 `GitTags.create(_:at:message:in:)` — lightweight, and annotated when a
      message is given. `recreate` already covers moving one; this is the half
      that was missing because a new tag had no row to right-click.
- [x] 1.2 `GitTags.delete(_:in:)`, locally and on the remote as separate asks.
- [x] 1.3 `GitCommits.revert`, `.cherryPick` and `.reset(to:mode:)`, each
      reporting a conflict as a conflict rather than as an exit code.
- [x] 1.4 Tests: a tag made at a commit, a tag made at a branch, a revert that
      applies, a cherry-pick that conflicts, a reset that moves the tip.
- [x] 1.5 The recreate sheet's text field becomes a picker over the refs already
      loaded — HEAD, local branches, tags newest first — still accepting typed
      text, with `GitTags.describe` resolving the choice beneath it. A source
      git cannot resolve says so rather than leaving the line blank: an empty
      line under a mistyped name looks exactly like one under a name that is
      fine. Verified with `--branch-rows tag-sources:v0.4.0`.
- [x] 1.6 The commit menu in the log gains checkout, branch-from-here, tag-here,
      revert, cherry-pick and reset — the last fenced off on its own, being the
      only one there that can lose work. A revert or cherry-pick that stops in a
      conflict is reported as a conflict with the files named and an Abort on
      the toast, not as a failure: it has already changed the work tree, and
      "that did not work" would be false about it. Verified with
      `--commit-menu 0`. **Move-a-tag-here is not done** — it wants the same
      picker 1.5 built, hung off a commit rather than a tag.

## 2. The safety net under them

**`git stash create` was the obvious mechanism and is the wrong one.** It has no
`--include-untracked` — the flag exists on `stash push` and not on `stash
create` — so a discard of a file git had never seen would have been "insured" by
a commit that did not contain it, and nothing on screen would have said so.
`captureWorkingCopy` does what `stash create` does one level down instead: a
throwaway `GIT_INDEX_FILE`, `add -A` into it, `write-tree`, `commit-tree`. That
reaches untracked files, still honours `.gitignore`, and leaves the real index
and the work tree alone. `capturesAFileGitHasNeverSeen` is the test that would
have caught it.

- [x] 2.1 `GitBackup.captureWorkingCopy(in:)` over `git stash create`, returning
      the commit it wrote, and nothing else touched.
- [x] 2.2 `GitBackup.keep(_:as:in:)` pointing a branch under `backup/` at a
      commit, named for the moment and the thing it holds.
- [x] 2.3 `GitBackup.sweep(olderThan:in:)`, and what it took, for the verb on the
      `backup/` folder.
- [x] 2.4 Tests: a capture leaves the working copy and the stash list alone; a
      kept ref is listed by `git branch`; a sweep takes only what is older.
- [x] 2.5 One place that decides what is destructive, so the list cannot drift.
      `GitDestructive.Operation` is closed and holds only the eight that can
      lose work — there is nowhere to add staging, stashing, fetching or
      creating, which is what stops the list growing. The wording lives with it
      rather than in a view, so what a dialog says can be read without a window;
      `oneOfSomethingIsNotOnes` caught "1 commit leave this branch" on the first
      run, which is the shape of mistake that survives review and reads as
      carelessness in a dialog somebody is being asked to trust.
- [x] 2.6 The dialogs, each leading with a count and naming the ref it will
      leave. Only the option that loses nothing carries a remember-this control.
- [x] 2.7 Force-pushing a branch states how many commits would be overwritten and
      claims no backup — the one destructive thing here that is not insured, and
      `GitDestructive` answers `nil` for its backup alone. The verb did not
      exist before this, so it arrives already guarded rather than being guarded
      afterwards. `--force-with-lease` and not `--force`: it refuses if the
      remote has moved since the app last looked, which is exactly the case
      where the count somebody was shown is already out of date.
- [x] 2.8 The toast afterwards, naming the ref and offering to undo.

## 3. Branch names fold on their slashes

- [x] 3.1 Generalise the tree builder in `GitChangeTree` over a path and a
      payload, leaving `GitChangeNode` as one use of it.
- [x] 3.2 A folder holding exactly one branch stays flat.
- [x] 3.3 Filtering flattens to full names.
- [x] 3.4 Tests: two branches under a prefix fold; one does not; a filter shows
      whole names and no folders; collapse state survives a rebuild.
- [x] 3.5 The branches list draws the folded tree — tags and `backup/` fold for
      free. **Flat rows from a tree rather than an `NSOutlineView`**, which is
      the intermediate and is deliberate: group 8 replaces this list wholesale
      with one outline holding the working copy and the stashes too, and an
      outline built now would be thrown away then. Folding is remembered by
      section *and* prefix, because `feature/` exists under Local and under
      every remote that has one.
      Verified in the running app with `--branch-rows`, against a scratchpad
      repository: `feature/` folds with two under it, `hotfix/0472` stays one
      row, `release/1.x/patch` folds the whole chain, `main` is promoted to the
      top, and filtering flattens to whole names with no folder rows.
- [x] 3.6 Verbs on a folder row: expand and collapse all, push all, delete
      merged, copy the prefix; delete-older-than on `backup/`.

## 4. Stashes made first class

- [x] 4.1 `GitStash.files(_:in:)` and `.diff(_:path:in:)` over a stash commit.
      **Untracked files are in a third parent, not in the diff.** A stash read
      only as `^1..stash` leaves out exactly the files somebody has forgotten
      they had, which is the worst possible thing for a preview to be quiet
      about. `aStashSaysWhichFilesGitHadNeverSeen` is the test.
- [x] 4.2 `GitStash.wouldApply(_:in:)`. **The design's open question, settled:
      `merge-tree --write-tree`, and the throwaway index is not needed at all.**
      A three-way merge in the object database answers the question without a
      work tree, so there is nothing to write and nothing to clean up. The side
      it merges into is the *working copy* rather than `HEAD` — the question is
      whether the stash goes back over what is there now — and
      `GitBackup.captureWorkingCopy` already gives the working copy a commit to
      stand for it, writing nothing. Old git has no `--write-tree`; `.unknown`
      is the answer there, because a check that guessed "clean" would be worse
      than no check.
- [x] 4.3 `GitStash.branch(_:named:in:)` over `git stash branch`.
- [x] 4.4 Tests: files of a stash; a clean check; a conflicting check naming the
      files; a branch from a stash that leaves the entry dropped.
- [x] 4.5 A stash row expands to its files; each opens that stash's diff.
- [x] 4.6 The clean-apply check on the row, and branch-from-stash offered where
      it says the apply would conflict.
- [x] 4.7 The dirty-tree checkout refusal offers stash-switch-restore, extending
      the principle `BranchInUse` already keeps. The refusal is recognised
      through `GitPull.refusal`, which already knows the several spellings git
      has for it — two lists of the same strings would drift, and the one that
      drifted would fail by showing git's raw refusal to somebody this could
      have helped. The stash is *named* (`Abydos: left on <branch>`) rather than
      numbered, so coming back can find it: every drop renumbers `stash@{n}`.
- [x] 4.8 Hunk-level stash through `GitPatch.patch(selecting:)` and
      `stash push --staged`, offered only where git is 2.35 or later — asked
      once when the window is built, so on an older git the menu item is absent
      rather than one that fails when pressed. It refuses while anything else is
      staged and says why: the index is how the hunks get to the stash, and
      sweeping up somebody's staging with them would be a surprise they could
      not undo.

## 5. Fetch, pull, and the dialog

- [x] 5.1 `GitFetch` and `GitPull`, with `--rebase` and `--autostash` as
      arguments rather than as configuration written behind somebody's back.
- [x] 5.2 Reading `pull.rebase` from the repository, so the dialog can open on
      what the project decided and say where that came from.
- [x] 5.3 A credential failure reported as one, rather than as an exit code with
      nothing said — `GIT_TERMINAL_PROMPT=0` makes silence the default.
- [x] 5.4 Tests: rebase and autostash reach the command line; the repository's
      setting outranks the app's; a credential failure is recognised.
- [x] 5.5 The dialog: remote and branch pickers, `Into:` stated and not editable,
      the two checkboxes, and the backup line under them.
- [x] 5.6 Settings: how this project pulls, whether to stash by default, and how
      long backup refs are kept.
- [x] 5.7 The ahead/behind counter in the git header, and what pressing it does
      at each of the three states.

## 6. The editor page, log tense

- [x] 6.1 A page in the editor area following `LaunchConfigurationsPage`, opened
      on ⇧⌘L. **Return on a ref is deliberately left to group 8**: activation in
      the refs list still means checkout, and changing that before the tree
      exists would leave checkout on the context menu alone for the length of
      the migration. The tree's activation semantics change there anyway.
- [x] 6.2 The graph at full width — lanes, refs, subject, author, age — with the
      selected commit's files and diff beside it rather than beneath it.
- [x] 6.3 `HistoryPane`'s loader, collapse rule and graph move across whole; no
      second model. **Structurally, not by promise: it is the same class.**
      `HistoryPane(root:layout:)` takes `.sidebar` or `.page`, so the loader,
      the collapse rule, the graph and the commit menu cannot drift apart —
      there is only one of each. What differs is the arrangement and two things
      the extra width buys: author and date as right-aligned columns rather than
      a second line, and the diff kept on the page instead of handed to a tab.

      Two bugs the work turned up, both now fixed: a stored `layout` property
      shadowed `NSView.layout()`, so the override that places the divider
      silently was not one; and a commit at the tip of four refs drew its last
      pill straight over the pane beside it, a row being drawn to its own bounds
      with nothing clipping it.
- [x] 6.4 The commit verbs from 1.6 sit on the page's rows.

## 7. The same page, commit tense

- [x] 7.1 The page pointed at what is staged: two lists, the diff beside them,
      and a message with room for a description.
- [x] 7.2 `ChangesPane`'s tree, staging, folder staging and discard move across
      whole — **structurally, as `HistoryPane` did: it is the same class.**
      `ChangesPane(root:layout:)` takes `.sidebar` or `.page`, so there is one
      tree and one discard question rather than two that drift.

      Discard now leaves a ref before it restores anything. The *question* stays
      `GitDiscard`'s: it names the folder and counts the files git has never
      seen, which no general dialog could — so what it borrows from the safety
      net is the insurance and the toast, not the wording.
- [x] 7.3 The sidebar keeps a one-line summary and a commit button, and opening
      the page carries what has been typed into it.
- [x] 7.4 `ClaudeDraft` in the kit: the staged diff and the last twenty subjects
      to `claude -p`, a summary and a description back, absent when `claude` is
      not on the `PATH`.
- [x] 7.5 Tests: what is sent is the staged diff and the recent subjects; an
      oversized diff names what it left out; a missing command is reported as
      absence rather than as failure.
- [x] 7.6 The drafting control on the page: never staging, never committing,
      never disabling commit while it thinks, and saying once per project that
      the diff is sent.

## 8. One tree, one tool item

- [x] 8.1 The refs tree gains the working copy as its first row, expanding to
      staged and unstaged and then to the folders they changed. Built from
      `GitChangeTree`, the same trees the commit page draws, so a folder here
      says "1 of 2" for the same reason and by the same arithmetic. Activating
      a file stages or unstages it; the message is written on the page.

      **Not yet moved across:** discarding, stashing selected files and
      ignoring, which stay on the commit page's menu. The tree stages and
      selects; it does not yet carry everything `ChangesPane`'s menu does.
- [x] 8.2 Stashes, local, each remote, tags, worktrees and `backup/` as sections
      of the same outline.
- [x] 8.3 Rows say enough unopened: ahead and behind and the tip's subject on a
      branch, the branch and age and apply-check on a stash, the target on a tag.
- [x] 8.4 The rail loses two buttons and the fence between them; Structure moves
      to ⌘3 and Scratches to ⌘4. **⌘5 and ⌘6 open the git tool and say where
      what they used to open has gone** — doing nothing would be the worse
      answer, because fingers do not read release notes.

      `SidebarToolKind` keeps `.changes` and `.history` behind the one button:
      the panes still exist — the driver reaches for them, and so does the
      popover when the terminal has the window — and the button lights for any
      of the three.
- [x] 8.5 The conflict banner in the header, naming the count, offering three
      things and no more: open the conflicted files, open in Fork, and copy a
      prompt describing the conflict for an agent in this app's own terminal.
      Not abort — that belongs on the operation that started the merge, where
      what would be lost can be counted.

## 9. Before it is finished

- [x] 9.1 `make test` clean, and its exit code read rather than its output.
      3270 tests in 434 suites, exit 0, at load 8.7. **Said with the load
      beside it**, because a run under load 18 with three copies of the app
      going had five git tests red and the same suites green in isolation at
      0.365 s — which is a number that cannot be told from a regression without
      the load written next to it.
- [x] 9.2 `make warnings` clean.
- [x] 9.3 The four open questions in `design.md` either answered in the spec or
      written down as still open, with what was learnt.
